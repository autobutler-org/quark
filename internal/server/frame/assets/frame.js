/*
 * Quark Frame (#3021): a light slideshow for a dedicated screen.
 *
 * Plain ES5 plus Promise and fetch, no framework, so it runs in a browser that is a few years old on a slow
 * chip. It signs in as the person using the screen (the same account and key derivation as the app), lists
 * that account's albums, and loops one of them. It only calls the existing /api/v0 routes.
 *
 * Address options: /frame?album=<id>&interval=<seconds>&order=shuffle|newest|oldest
 */
(function (root) {
  'use strict';

  var API = '/api/v0';
  var STORE = 'quarkFrame';
  var DEFAULT_INTERVAL = 15;
  var REFRESH_MS = 10 * 60 * 1000;
  var RETRY_MS = 30 * 1000;
  var MENU_MS = 10 * 1000;
  var FADE_MS = 1500;

  // Shown as they are. RAW is asked for as a JPEG, and HEIC shows its stored thumbnail: the Quark does not decode
  // HEIC (#2382). Anything else (video, documents) is skipped.
  var SHOWN = /\.(jpe?g|png|gif|webp|bmp|avif)$/i;
  var CONVERTED = /\.(dng|cr2|cr3|nef|arw|orf|rw2|raf)$/i;
  var HEIC = /\.hei[cf]$/i;

  var state = {
    album: null,
    items: [],
    index: 0,
    front: null,
    pending: null,
    waiting: false,
    failures: 0,
    timer: null,
    refresh: null,
    menu: null,
    sodium: null
  };

  // ---- Key derivation. Must stay byte-identical to lib/services/chat_crypto.dart and the server. ----

  // authKey = HKDF-SHA256(Argon2id13(password, salt, 3 passes, 64 MiB), no salt, info "auth"), standard base64.
  // HKDF with an empty salt keys the extract step with 32 zero bytes; one expand block gives the 32 output bytes.
  function deriveAuthKey(sodium, password, saltBase64) {
    var salt = sodium.from_base64(saltBase64, sodium.base64_variants.ORIGINAL);
    var master = sodium.crypto_pwhash(32, password, salt, 3, 64 * 1024 * 1024, sodium.crypto_pwhash_ALG_ARGON2ID13);
    var prk = sodium.crypto_auth_hmacsha256(master, new Uint8Array(32));
    var info = new Uint8Array([97, 117, 116, 104, 1]); // "auth" then the block counter 1
    return sodium.to_base64(sodium.crypto_auth_hmacsha256(info, prk), sodium.base64_variants.ORIGINAL);
  }

  // ---- Photos ----

  function playable(item) {
    return !!item && typeof item.relPath === 'string' && (SHOWN.test(item.relPath) || CONVERTED.test(item.relPath) || HEIC.test(item.relPath));
  }

  function photoUrl(item) {
    var serial = item.deviceSerial ? '&serial=' + encodeURIComponent(item.deviceSerial) : '';
    if (HEIC.test(item.relPath)) {
      var path = item.relPath.replace(/^\/+/, '').split('/').map(encodeURIComponent).join('/');
      return API + '/thumbnails/' + path + '?size=lg' + serial;
    }
    var url = API + '/files/download?filePath=' + encodeURIComponent(item.relPath) + serial;
    return CONVERTED.test(item.relPath) ? url + '&format=jpeg' : url;
  }

  function shuffled(list) {
    var out = list.slice();
    for (var i = out.length - 1; i > 0; i -= 1) {
      var j = Math.floor(Math.random() * (i + 1));
      var swap = out[i];
      out[i] = out[j];
      out[j] = swap;
    }
    return out;
  }

  // ---- Page helpers ----

  function el(id) {
    return document.getElementById(id);
  }

  function option(name) {
    var pairs = (root.location.search || '').replace(/^\?/, '').split('&');
    for (var i = 0; i < pairs.length; i += 1) {
      var pair = pairs[i].split('=');
      if (decodeURIComponent(pair[0]) === name) {
        return decodeURIComponent(pair.slice(1).join('=') || '');
      }
    }
    return '';
  }

  function read() {
    try {
      return JSON.parse(root.localStorage.getItem(STORE)) || {};
    } catch (e) {
      return {};
    }
  }

  function write(patch) {
    var saved = read();
    for (var key in patch) {
      if (Object.prototype.hasOwnProperty.call(patch, key)) {
        saved[key] = patch[key];
      }
    }
    try {
      root.localStorage.setItem(STORE, JSON.stringify(saved));
    } catch (e) {
      /* a private window or full storage: the page still works, it just forgets */
    }
  }

  function showOnly(id) {
    var ids = ['signin', 'chooser', 'show'];
    for (var i = 0; i < ids.length; i += 1) {
      el(ids[i]).hidden = ids[i] !== id;
    }
  }

  function say(text, isError) {
    var status = el('status');
    status.textContent = text || '';
    status.className = isError ? 'error' : '';
  }

  function stop() {
    root.clearTimeout(state.timer);
    root.clearTimeout(state.refresh);
    root.clearTimeout(state.menu);
    state.pending = null;
    state.waiting = false;
  }

  function api(method, path, body) {
    var init = { method: method, credentials: 'same-origin', headers: {} };
    if (body !== undefined) {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }
    return root.fetch(API + path, init).then(function (response) {
      return response.text().then(function (text) {
        var data = null;
        try {
          data = text ? JSON.parse(text) : null;
        } catch (e) {
          data = null;
        }
        return { status: response.status, data: data, retryAfter: response.headers.get('Retry-After') };
      });
    });
  }

  function reason(result) {
    return result && result.data && result.data.error ? result.data.error : '';
  }

  // ---- Sign-in ----

  function loadSodium() {
    if (!state.sodium) {
      state.sodium = new Promise(function (resolve, reject) {
        if (root.sodium && root.sodium.ready) {
          resolve(root.sodium.ready.then(function () { return root.sodium; }));
          return;
        }
        var script = document.createElement('script');
        script.src = '/sodium.js';
        script.onload = function () {
          root.sodium.ready.then(function () { resolve(root.sodium); }, reject);
        };
        script.onerror = function () { reject(new Error('sodium')); };
        document.head.appendChild(script);
      });
    }
    return state.sodium;
  }

  function showSignin(message) {
    stop();
    showOnly('signin');
    el('signin-button').disabled = false;
    el('password').value = '';
    el('username').value = el('username').value || read().username || '';
    say(message || '', !!message);
    (el('username').value ? el('password') : el('username')).focus();
  }

  function signIn(username, password) {
    var button = el('signin-button');
    button.disabled = true;
    say('Getting ready...');
    return api('GET', '/auth/salt?username=' + encodeURIComponent(username))
      .then(function (salt) {
        if (salt.status !== 200 || !salt.data) {
          throw new Error(salt.status === 429 ? 'Too many tries. Wait a minute and try again.' : "Can't reach Quark.");
        }
        if (salt.data.legacy) {
          throw new Error('This account has to sign in once from the Quark app first.');
        }
        return loadSodium().then(function (sodium) {
          say('Signing in. This takes about ten seconds on a small screen...');
          return new Promise(function (resolve) {
            // Let the message paint before the CPU is busy.
            root.setTimeout(function () { resolve(deriveAuthKey(sodium, password, salt.data.salt)); }, 80);
          });
        });
      })
      .then(function (authKey) {
        return api('POST', '/auth/login', { username: username, authKey: authKey });
      })
      .then(function (login) {
        if (login.status === 200) {
          write({ username: username });
          return begin();
        }
        if (login.status === 401) {
          throw new Error("That username or password isn't right.");
        }
        if (login.status === 429) {
          throw new Error('Too many tries. Try again in ' + (login.retryAfter || 'a few') + ' seconds.');
        }
        throw new Error(reason(login) || "Couldn't sign in.");
      })
      .catch(function (error) {
        button.disabled = false;
        el('password').value = '';
        say(error && error.message ? error.message : "Couldn't sign in.", true);
      });
  }

  function signOut() {
    stop();
    return api('POST', '/auth/logout').then(function () {
      write({ album: null });
      showSignin('');
    }, function () {
      showSignin('');
    });
  }

  // ---- Albums ----

  function fullscreen() {
    var page = document.documentElement;
    var request = page.requestFullscreen || page.webkitRequestFullscreen || page.mozRequestFullScreen;
    if (request) {
      try {
        request.call(page);
      } catch (e) {
        /* the browser refused; the page works without it */
      }
    }
  }

  function showChooser(albums) {
    stop();
    var list = el('albums');
    list.innerHTML = '';
    albums.forEach(function (album) {
      var item = document.createElement('li');
      var button = document.createElement('button');
      button.type = 'button';
      button.appendChild(document.createTextNode(album.name));
      var count = document.createElement('div');
      count.className = 'count';
      count.textContent = album.itemCount === 1 ? '1 photo' : album.itemCount + ' photos';
      button.appendChild(count);
      button.onclick = function () {
        fullscreen();
        write({ album: { id: album.id, name: album.name } });
        play(album);
      };
      item.appendChild(button);
      list.appendChild(item);
    });
    showOnly('chooser');
    say(albums.length ? '' : 'There are no albums yet. Make one in Quark, then come back.');
  }

  function begin() {
    say('Loading...');
    return api('GET', '/albums').then(function (albums) {
      if (albums.status === 401) {
        return showSignin('');
      }
      if (albums.status !== 200 || !albums.data) {
        say("Can't reach Quark. Trying again soon.", true);
        state.timer = root.setTimeout(begin, RETRY_MS);
        return null;
      }
      var wanted = option('album') ? { id: parseInt(option('album'), 10) } : read().album;
      var match = null;
      albums.data.forEach(function (album) {
        if (wanted && album.id === wanted.id) {
          match = album;
        }
      });
      if (match) {
        return play(match);
      }
      return showChooser(albums.data);
    }, function () {
      say("Can't reach Quark. Trying again soon.", true);
      state.timer = root.setTimeout(begin, RETRY_MS);
    });
  }

  // ---- Slideshow ----

  function interval() {
    var seconds = parseInt(option('interval'), 10);
    return (seconds > 0 ? seconds : DEFAULT_INTERVAL) * 1000;
  }

  function load(album) {
    var order = option('order') || 'shuffle';
    var query = order === 'oldest' ? '?sort=taken&order=asc' : '?sort=taken&order=desc';
    return api('GET', '/albums/' + album.id + '/items' + query).then(function (result) {
      if (result.status === 401) {
        showSignin('Please sign in again.');
        return false;
      }
      if (result.status !== 200 || !result.data) {
        throw new Error(reason(result) || "Couldn't load " + album.name + '.');
      }
      var photos = result.data.filter(playable);
      state.items = order === 'shuffle' ? shuffled(photos) : photos;
      return true;
    });
  }

  function play(album) {
    stop();
    state.album = album;
    state.index = 0;
    state.failures = 0;
    state.front = null;
    el('layer-a').className = '';
    el('layer-b').className = '';
    showOnly('show');
    say('');
    return load(album).then(function (ok) {
      if (!ok) {
        return;
      }
      if (!state.items.length) {
        say(album.name + ' has no photos to show yet.');
        state.timer = root.setTimeout(function () { play(album); }, RETRY_MS);
        return;
      }
      state.waiting = true;
      prepare();
      state.refresh = root.setTimeout(refreshItems, REFRESH_MS);
    }, function (error) {
      say(error.message, true);
      state.timer = root.setTimeout(function () { play(album); }, RETRY_MS);
    });
  }

  function refreshItems() {
    var album = state.album;
    if (!album) {
      return;
    }
    load(album).then(function () {
      state.index = 0;
    }, function () {
      /* keep what is showing; try again at the next refresh */
    }).then(function () {
      if (state.album === album) {
        state.refresh = root.setTimeout(refreshItems, REFRESH_MS);
      }
    });
  }

  function back() {
    return state.front === 'layer-a' ? el('layer-b') : el('layer-a');
  }

  // Fills the hidden layer with the next photo, so it is ready when the timer fires.
  function prepare() {
    if (!state.items.length) {
      return;
    }
    var item = state.items[state.index % state.items.length];
    state.index += 1;
    var layer = back();
    var pending = { ready: false };
    state.pending = pending;
    layer.onload = function () {
      if (state.pending !== pending) {
        return;
      }
      pending.ready = true;
      state.failures = 0;
      if (state.waiting) {
        reveal();
      }
    };
    layer.onerror = function () {
      if (state.pending !== pending) {
        return;
      }
      state.failures += 1;
      if (state.failures >= state.items.length) {
        say("Can't load any of these photos. Trying again soon.", true);
        state.timer = root.setTimeout(function () { play(state.album); }, RETRY_MS);
        return;
      }
      prepare();
    };
    layer.src = photoUrl(item);
  }

  function reveal() {
    state.waiting = false;
    state.pending = null;
    var next = back();
    var old = state.front ? el(state.front) : null;
    next.className = 'visible';
    if (old) {
      old.className = '';
      root.setTimeout(function () {
        // Let go of the old picture once it has faded out, so a small device is not holding two.
        if (old.className === '') {
          old.removeAttribute('src');
        }
      }, FADE_MS);
    }
    state.front = next.id;
    say('');
    root.clearTimeout(state.timer);
    state.timer = root.setTimeout(tick, interval());
    root.setTimeout(function () {
      if (state.front === next.id) {
        prepare();
      }
    }, FADE_MS);
  }

  function tick() {
    if (state.pending && state.pending.ready) {
      reveal();
    } else {
      state.waiting = true;
    }
  }

  // ---- Menu: a tap on the picture opens it, and it closes itself. ----

  function menu(open) {
    el('menu').hidden = !open;
    root.clearTimeout(state.menu);
    if (open) {
      state.menu = root.setTimeout(function () { menu(false); }, MENU_MS);
    }
  }

  function wire() {
    el('signin-form').onsubmit = function (event) {
      event.preventDefault();
      signIn(el('username').value.trim(), el('password').value);
      return false;
    };
    el('chooser-signout').onclick = signOut;
    el('show').onclick = function () { menu(el('menu').hidden); };
    function onMenu(id, action) {
      el(id).onclick = function (event) {
        event.stopPropagation();
        action();
      };
    }
    onMenu('menu-close', function () { menu(false); });
    onMenu('menu-fullscreen', function () { fullscreen(); menu(false); });
    onMenu('menu-signout', function () { menu(false); signOut(); });
    onMenu('menu-albums', function () {
      menu(false);
      write({ album: null });
      begin();
    });
  }

  function init() {
    wire();
    begin();
  }

  var exported = { deriveAuthKey: deriveAuthKey, playable: playable, photoUrl: photoUrl, shuffled: shuffled };
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = exported;
  } else {
    root.QuarkFrame = exported;
  }
  if (root.document && root.document.getElementById && root.document.getElementById('app')) {
    init();
  }
})(typeof window !== 'undefined' ? window : this);
