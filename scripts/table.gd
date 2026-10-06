# Géométrie de la table, partagée par le serveur, les ordinateurs et l'affichage.
# Repère : centre de la table en (0, 0) ; une position sur la table est un Vector2 (x, z).

const TABLE_SIZE := 1.3
const SEAT_RADIUS := 0.55
const RIGHT_HAND_LOCAL := Vector2(0.19, -0.14)  # main droite au repos, dans le repère du siège
const HAND_RADIUS := 0.045                     # rayon de la paume
const CIRCLE_RADIUS := TABLE_SIZE / 4.0         # cercle rouge : la moitié de la table en diamètre
const LINE_TOLERANCE := 0.02                    # au-delà, la main a franchi la ligne


# Angle du siège : le joueur 0 est en +z, puis dans le sens des aiguilles d'une montre vu du dessus.
static func seat_angle(seat: int) -> float:
	return -seat * PI / 2.0


static func right_hand_rest(seat: int) -> Vector2:
	var a := seat_angle(seat)
	var center := Vector2(sin(a), cos(a)) * SEAT_RADIUS
	# Rotation de yaw autour de l'axe vertical : (x, z) tourne de -yaw dans le plan.
	return center + RIGHT_HAND_LOCAL.rotated(-a)


# De combien la paume empiète sur le cercle (négatif : elle ne le touche pas).
static func intrusion(pos: Vector2) -> float:
	return CIRCLE_RADIUS + HAND_RADIUS - pos.length()


# Point juste à l'extérieur du cercle, dans la direction de pos.
static func outside_circle(pos: Vector2) -> Vector2:
	var direction := pos.normalized() if pos.length() > 0.001 else Vector2(0, 1)
	return direction * maxf(pos.length(), CIRCLE_RADIUS + HAND_RADIUS + 0.01)
