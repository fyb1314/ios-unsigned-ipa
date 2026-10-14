import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(minWidth: 88, alignment: .leading)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}
