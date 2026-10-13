extension String {
    /// `"AIR_DRY"` → `"Air Dry"`: the fallback display name for profile values we have no
    /// curated name for.
    var enumConstantDisplayName: String {
        split(separator: "_")
            .map { word in word.prefix(1).uppercased() + word.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
