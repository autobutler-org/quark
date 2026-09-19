paths = {
  "perf/sample-1.jpg",
  "perf/nested/file-1.txt",
  "perf/blob-1.bin"
}

counter = 0

request = function()
  counter = counter + 1
  local idx = (counter % #paths) + 1
  return wrk.format("GET", "/api/v0/files/stat?filePath=" .. paths[idx])
end
