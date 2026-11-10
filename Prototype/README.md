# Fluvial Strike

Bêta Windows 0.1.0. Pour jouer à la version autonome, extraire le ZIP de la [préversion GitHub](https://github.com/Kraran/FluvialStrike/releases/tag/v0.1.0) et ouvrir **Fluvial Strike.exe**. Pour lancer les sources avec Godot 4.7.2, importer `project.godot` ou utiliser `../Lancer Fluvial Strike.bat` si Godot est disponible sur le PC.

Le raid traverse neuf ponts avant la fin du parcours. Le trajet de validation dure environ 2 min 22 s. Le rendu 3D orthographique utilise le tracé des berges relevé dans Stella. L’eau, les matériaux, les modèles, les effets et les sons sont générés localement dans Godot. La simulation tourne à 60 pas par seconde. Les chenaux et les rencontres des secteurs supplémentaires proviennent de la ROM européenne. Les trajectoires sont interpolées à partir de relevés et les collisions restent approximatives.

## Commandes en jeu

| Action | Clavier | Manette |
| --- | --- | --- |
| Se déplacer | ← / → | Stick gauche ou croix |
| Accélérer / ralentir | ↑ / ↓ | Stick gauche ou croix |
| Tirer | Espace | Bouton du bas |
| Pause / reprise | Échap | Start |
| Repartir du début | R | |
| Voir le rejeu de référence jusqu’au premier îlot | F5 | |
| Rejouer le dernier vol manuel de la session | F6 | |
| Afficher les collisions et les mesures | F1 | |
| Couper ou rétablir le son | M | |

## Réglages et record

Le menu **Réglages** est accessible depuis l’accueil et la pause. Il propose le plein écran, la synchronisation verticale, le rendu HD et le volume. Désactiver **Rendu HD** réduit la résolution de la scène 3D et désactive son anticrénelage. Le cadrage et la simulation gardent les mêmes proportions.

Pour changer une commande, sélectionner la touche ou le bouton correspondant, puis appuyer sur sa nouvelle affectation. Une affectation déjà utilisée est permutée avec l’ancienne. Le stick gauche conserve ses directions. **Échap** annule une affectation en cours. Les réglages sont enregistrés à la sortie de l’écran.

Le record local se met à jour à la fin d’un vol manuel. Les rejeux ne le modifient pas. Godot conserve les réglages et le record dans `user://fluvial_strike.cfg`.

## Vérification

Le rejeu de référence utilise les commandes de la fiche `../REFERENCE_GAMEPLAY.md`. Il dure 809 images. Il se termine en section 2 avec 930 points, 3 réserves, 50 847 unités de carburant et une abscisse native de 56. La suite compare aussi les images de chaque gain de score, la réponse latérale, le ravitaillement et les reprises des deux côtés du pont. Un second rejeu pilote le raid complet dans Godot, avec un test de reprise après le cinquième pont.

Avec le binaire console de Godot, depuis ce dossier, exécuter la commande suivante. Le test renvoie un code d’erreur si une vérification échoue.

```powershell
godot --headless --path . --script res://verify.gd
```

Les données de vol sont incluses dans `course.gd` et `course_extension.gd`. Le projet se lance avec Godot Standard, sans Blender, Stella, vidéo ni ROM.

## Export Windows

Dans l’éditeur Godot 4.7.2, installer le modèle Windows x86_64 dans le gestionnaire de modèles d’export. Puis choisir **Projet → Exporter → Windows x64** et exporter **Fluvial Strike.exe** en mode release. Distribuer l’exécutable avec le fichier `Fluvial Strike.pck`, le guide de lancement et les avis de licence fournis dans le ZIP de livraison.
