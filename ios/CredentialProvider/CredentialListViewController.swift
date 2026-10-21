import QuarkVaultCrypto
import UIKit

/// The extension's one screen: a spinner while the vault opens, the matching logins, or one sentence saying
/// what to do. It holds names and usernames only; the password is opened when a row is picked.
final class CredentialListViewController: UITableViewController {
    /// One login in the list.
    struct Row {
        let entry: VaultAutofillEntry
        let title: String
        let subtitle: String
    }

    enum State {
        case loading
        case message(String)
        case rows([Row], footer: String?)
    }

    var onCancel: (() -> Void)?
    var onSelect: ((VaultAutofillEntry) -> Void)?

    private var rows: [Row] = []
    private var footer: String?

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AutofillCopy.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )
    }

    func show(_ state: State) {
        switch state {
        case .loading:
            rows = []
            footer = nil
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            tableView.backgroundView = spinner
        case let .message(text):
            rows = []
            footer = nil
            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            let container = UIView()
            container.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.readableContentGuide.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: container.readableContentGuide.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            tableView.backgroundView = container
        case let .rows(newRows, newFooter):
            rows = newRows
            footer = newFooter
            tableView.backgroundView = nil
        }
        tableView.reloadData()
    }

    @objc private func cancel() {
        onCancel?()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        rows.isEmpty ? 0 : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "login")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "login")
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(rows[indexPath.row].entry)
    }
}
