import UIKit
import SwiftUI

/// A temporary, noninteractive hint beside the final page, not a bottom toolbar.
final class PageCreationIndicator: UIVisualEffectView {
    private let icon = UIImageView(image: UIImage(systemName: "plus.circle"))
    private let progress = UIProgressView(progressViewStyle: .default)
    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        layer.cornerRadius = 16; clipsToBounds = true
        isUserInteractionEnabled = false; isHidden = true
        let label = UILabel()
        label.text = "Hold to add a page"
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .label
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.textAlignment = .center
        icon.contentMode = .scaleAspectFit
        icon.tintColor = AppPreferences.shared.accentUIColor
        progress.progressTintColor = AppPreferences.shared.accentUIColor
        let stack = UIStackView(arrangedSubviews: [icon, label, progress])
        stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.heightAnchor.constraint(equalToConstant: 22),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Hold to add a page"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func show(progress value: Double?) {
        isHidden = value == nil
        guard let value else { return }
        let accent = AppPreferences.shared.accentUIColor
        if icon.tintColor !== accent { icon.tintColor = accent; progress.progressTintColor = accent }
        progress.setProgress(Float(value), animated: false)
        accessibilityValue = "\(Int(value * 100)) percent"
    }
}
