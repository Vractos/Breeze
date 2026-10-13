import SwiftUI

/// The inline outcome of "Test connection" / "Refresh list".
struct ConnectionTestResultLabel: View {
    let result: ACStore.ConnectionTestResult

    var body: some View {
        Label {
            Text(result.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: result.symbolName)
                .foregroundStyle(result.isSuccess ? Color.green : Color.orange)
        }
        .font(.callout)
    }
}
