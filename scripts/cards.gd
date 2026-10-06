# Outils pour les cartes d'un jeu de 52.
# Une carte est un entier de 0 à 51 : valeur = carte % 13, couleur = carte / 13.

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"]
const SUITS := ["♠", "♥", "♦", "♣"]


static func rank(card: int) -> int:
	return card % 13


@warning_ignore("integer_division")
static func suit(card: int) -> int:
	return card / 13


static func is_red(card: int) -> bool:
	var s := suit(card)
	return s == 1 or s == 2


static func text(card: int) -> String:
	return "%s\n%s" % [RANKS[rank(card)], SUITS[suit(card)]]


static func is_face(card: int) -> bool:
	return rank(card) >= 10  # valet, dame, roi


# Deux cartes qui se suivent forment une paire : même valeur, ou deux têtes.
static func forms_pair(a: int, b: int) -> bool:
	return rank(a) == rank(b) or (is_face(a) and is_face(b))


# Dimensions d'une carte sur la table (mètres), utilisées pour l'affichage et pour juger les tapes.
const CARD_W := 0.11
const CARD_L := 0.155
