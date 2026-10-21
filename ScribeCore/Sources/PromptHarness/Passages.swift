/// Sample paragraphs covering several registers, so every Target meets text it should
/// and shouldn't like.
struct Passage {
    let name: String
    let text: String
}

enum Passages {
    static let all: [Passage] = [
        Passage(name: "colloquial", text: """
            The rain was really bad that night and it kind of made everything a mess, honestly. \
            We just sat there in the car for ages, like, not even talking, because what was there to say? \
            It was a total disaster and nobody wanted to be the one to admit it.
            """),
        Passage(name: "purple", text: """
            The crimson-gold sunset bled its molten, achingly beautiful fire across the shimmering, \
            velvet-dark waters, and her heart, that trembling, fragile, luminous bird, soared and wept \
            and soared again in a rapturous, ineffable symphony of longing that no mortal tongue could ever name.
            """),
        Passage(name: "academic", text: """
            These findings suggest that the relationship between urban density and civic participation is \
            mediated by the availability of shared public space, rather than by density itself. \
            However, because the sample was drawn from three comparable municipalities, the extent to which \
            the effect generalises to rural contexts remains uncertain.
            """),
        Passage(name: "middle-grade", text: """
            Maya grabbed the flashlight and ran. The tunnel was dark and smelled like old pennies. \
            "Wait for me!" shouted Leo, but she didn't stop. Somewhere ahead, something was scratching. \
            She took a deep breath, pointed the light, and gasped.
            """),
        Passage(name: "economist", text: """
            Central bankers like to say they are data-dependent. The data are not cooperating. \
            Inflation has fallen faster than most forecasters expected, yet wages are still rising by 5% a year. \
            Rate-setters must now decide whether to declare victory early or risk keeping policy too tight for too long.
            """),
        Passage(name: "bloated", text: """
            In this particular paragraph, which I am writing at this point in time, I would like to basically \
            take the opportunity to essentially point out the fact that, in my own personal opinion, it is \
            really quite important for each and every one of us to actually make an effort to try to be more concise.
            """),
    ]
}
