# Nervous

Jeu de cartes de rapidité en 3D, vu à la première personne (Godot 4).

- Règles : [docs/regles.md](docs/regles.md)
- Lancer : ouvrir le dossier dans Godot 4.7, puis F5.
- Tests : `Godot --headless --path . --script res://tests/test_rules.gd` (aussi `test_server.gd`, `test_simulation.gd`)
- Sons : `Godot --headless --path . --script res://tools/generate_sounds.gd` puis `Godot --headless --path . --import`

## Version à envoyer (Windows)

- Exporter : `Godot --headless --path . --export-release "Windows Desktop" build/Nervous.exe` (modèles d'export Godot 4.7.2 requis).
- Résultat : `build/Nervous.exe`, un seul fichier (non versionné) à envoyer aux amis.
- Au premier lancement, Windows peut afficher « Windows a protégé votre ordinateur » (jeu non signé) : « Informations complémentaires » puis « Exécuter quand même ». Il peut aussi demander d'autoriser le jeu sur le réseau : accepter.
