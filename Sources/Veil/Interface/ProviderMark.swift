import Allowance
import SwiftUI

struct ProviderMark: View {
  let provider: Provider
  var size: CGFloat = 23

  private static let openAI = NSImage(
    contentsOf: Bundle.module.url(forResource: "OpenAI", withExtension: "svg")!
  )!
  private static let claude = NSImage(
    contentsOf: Bundle.module.url(forResource: "Claude", withExtension: "svg")!
  )!

  var body: some View {
    Image(nsImage: provider == .codex ? Self.openAI : Self.claude)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

extension Provider {
  var accentColor: Color {
    switch self {
    case .codex: .blue
    case .claude: Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    }
  }
}
