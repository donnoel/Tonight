import Foundation

enum TVStarterLibrary {
    static let titles = """
    American Horror Story (Seasons 1-3)
    Battlestar Galactica (2004)
    Beavis and Butt-Head
    Better Call Saul
    Billions
    Breaking Bad
    Californication
    Chappelle's Show
    Cosmos (1980)
    Curb Your Enthusiasm
    Death Note (2006)
    Devs
    Dexter
    Eastbound & Down
    Entourage (2004)
    Frasier (1993)
    Game of Thrones
    Hannibal
    It's Always Sunny in Philadelphia (Seasons 1-4)
    Key & Peele
    Killing Eve (2018)
    Legion
    Lost (2004)
    Mad Men
    Mr. Robot
    Parks and Recreation
    Portlandia (Seasons 1-6)
    Seinfeld
    Silicon Valley
    Six Feet Under
    Star Trek (1966)
    The Boys (2019)
    The Outer Limits (1963)
    The Sopranos
    The Twilight Zone (1959)
    True Blood
    Veep
    Westworld
    Yellowstone (2018)
    """

    /// Explicit user confirmations for entries already imported without a version year.
    static let confirmedVersions = """
    Entourage (2004)
    Killing Eve (2018)
    Lost (2004)
    The Boys (2019)
    Yellowstone (2018)
    """

    static func viewingStyle(for title: String) -> TVViewingStyle {
        let standalone = ["Beavis and Butt-Head", "Chappelle's Show", "Cosmos", "Curb Your Enthusiasm",
                          "Frasier", "It's Always Sunny in Philadelphia", "Key & Peele", "Portlandia",
                          "Seinfeld", "Star Trek", "The Outer Limits", "The Simpsons", "The Twilight Zone"]
        if standalone.map(MovieTitleNormalizer.normalize).contains(MovieTitleNormalizer.normalize(title)) {
            return .anyEpisode
        }
        return MovieTitleNormalizer.normalize(title) == MovieTitleNormalizer.normalize("American Horror Story")
            ? .bySeason : .inOrder
    }
}
