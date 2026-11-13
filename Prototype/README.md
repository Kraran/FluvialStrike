# Fluvial Strike

Bêta Windows 0.2.51. Pour jouer à la version autonome, extraire le [ZIP Windows x64](https://github.com/Kraran/FluvialStrike/releases/download/v0.2.51/Fluvial-Strike-0.2.51-win64.zip) et ouvrir **Fluvial Strike.exe**. Pour lancer les sources avec Godot 4.7.2, double-cliquer sur `../Lancer Fluvial Strike.bat`.

Le raid se poursuit jusqu’à la perte des réserves ou au plafond d’un million de points. Les données couvrent les 2 000 ponts nécessaires pour inclure tout le parcours jouable avant ce plafond. Le générateur de la cartouche européenne fournit les berges, les îlots et le placement initial des cibles après les relevés Stella des neuf premiers ponts. Les mouvements des nouveaux ennemis et les collisions suivent la simulation Godot à 60 pas par seconde. Le décor se charge autour de l’avion au fil du vol. [Désassemblage annoté de la cartouche Atari 2600](https://github.com/johnidm/asm-atari-2600/blob/master/riverraid.asm)


L’avion du joueur reprend le B-1 StratoWing de l’illustration fournie comme référence visuelle. Le modèle 3D utilise un fuselage métallique, une verrière bombée, des ailes rouges à flèche, des marquages clairs et une dérive unique. Ses proportions et ses détails sont interprétés à partir de cette vue, puis adaptés au cadrage du jeu. Les pièces sont regroupées en huit maillages par matériau.

Les chasseurs ennemis reprennent la silhouette du MiG-29 de la photo fournie, avec deux dérives, deux tuyères et un camouflage gris-vert. Leur altitude de rendu les place au-dessus de la cime des arbres.

Les hélicoptères ennemis ont un fuselage olive, une verrière arrondie, des patins et deux rotors animés. Les repères ocre sur les pales et le fuselage aident à les distinguer au-dessus de la rivière.

Les navires ennemis ont un pont détaillé, une passerelle vitrée et un sillage d’écume animé. Leur proue s’oriente dans le sens du déplacement.

Les ponts ont des culées en béton et un tablier porté par des poutres à treillis. Après l’explosion, les culées marquent l’ouverture de part et d’autre de la rivière.

Deux traînées légères se forment aux extrémités des ailes du StratoWing. Plus visibles à grande vitesse, elles s’estompent derrière l’avion pendant les virages.

Les berges gardent une identité cohérente pendant trois sections à la fois. La végétation, la teinte du sol et les petits reliefs évoluent par touches sur l’ensemble du parcours. À partir de la section 04, un seul repère peut apparaître par bloc de trois sections, avec des blocs sans repère. Le camion de lancement, la rampe et le dirigeable amarré restent des éléments de décor.

Le décor comprend trois silhouettes d’arbres, des buissons, des rochers et des hameaux avec maisons et bâtiments agricoles ou industriels. Les troncs, les houppiers, les tailles et les teintes varient. Un léger mouvement du feuillage est calculé sur le GPU. Les bâtiments sont regroupés par prototype et les arbres par espèce dans des MultiMesh découpés en secteurs.

La rivière présente des rides dans le sens du courant et des filets d’écume qui suivent le contour des berges et des îlots.

Les berges et les extrémités des îlots utilisent une carte de distance filtrée, échantillonnée sur le GPU pour les pentes, les sols humides et les hauts-fonds. Le lissage porte sur le rendu et peut s’écarter légèrement des limites de collision issues du tracé de référence. La carte du décor sert aussi au placement des bâtiments, dont les emprises sont vérifiées sur la terre ferme et à distance des routes.

Le moteur module sa turbine selon la vitesse de l’avion. Les tirs, les impacts et les éclaboussures ont chacun leur son. À la destruction d’un pont, le bruit de la chute se déclenche au premier contact des débris avec l’eau.

Les barges industrielles portent le repère **FUEL** noir sur fond jaune, intégré à la texture du pont. La jauge confirme le ravitaillement pendant le survol et passe à l’ambre sous le seuil de réserve.

Les explosions, les impacts et les éclaboussures sont placés entre les canaux gauche et droit selon leur position à l’écran. Le jet, l’hélicoptère et le navire les plus présents dans le champ ont chacun une boucle sonore. Le rotor se fait entendre à l’approche du StratoWing, atteint son niveau maximal au passage et s’estompe ensuite, même quand l’hélicoptère sort du cadre. Les alertes et la turbine du joueur restent centrées.

Le **Hangar** propose cinq avions. L’aperçu reprend le modèle du jeu et le choix est mémorisé. Chaque avion utilise la même simulation de vol.

Le tableau de bord met en avant le carburant. Les deux cadrans indiquent la vitesse de simulation et l’inclinaison visible de l’avion. Le meilleur score apparaît sous le score de la partie.

La manette active réagit à la destruction d’un pont, au début du ravitaillement et aux collisions. Le curseur **Vibrations** des Réglages ajuste l’intensité. À **0 %**, les vibrations sont coupées.

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

## Rejeux des raids

**Archives → Rejeux** permet de revoir le meilleur raid manuel sans code, avec l’avion utilisé lors de cette partie. Le rejeu est enregistré avec le score local. **Rejeu du dernier raid** conserve la dernière partie manuelle terminée, y compris avec des codes, et reste disponible après redémarrage. Les anciens scores acquièrent un rejeu lorsqu’une nouvelle partie les égale ou les dépasse.

Pendant un rejeu, **← / LB** ramène à l’approche du pont précédent et **→ / RB** passe au pont suivant. Maintenir le stick gauche, la croix directionnelle ou les flèches **↑ / ↓** pour faire varier progressivement la vitesse de 0,25× à 3×. Au relâchement, la lecture revient progressivement à 1×.

## Navigation et meilleur score

L’accueil propose six entrées en colonne : **Raid solo**, **Deux joueurs**, **Hangar**, **Archives**, **Réglages** et **Quitter**. Une carte à droite montre l’avion choisi ; **LB / RB** ou **Page préc. / suiv.** en changent sans passer par le Hangar. **Start** lance un raid solo quel que soit l’élément sélectionné, **Y** ouvre le Hangar, **View** ou **Tab** ouvre l’aide-mémoire des commandes, et **B** ou **Échap** place le curseur sur **Quitter**. **Archives** regroupe le **Classement** et les **Rejeux** du meilleur et du dernier raid, en deux onglets parcourus avec **LB / RB** ; un rejeu indisponible reste sélectionnable et la raison s’affiche sous la liste. La pause indique la section atteinte et le score du raid en cours, et propose aussi l’aide-mémoire **Commandes**.

Dans les menus, **↑ / ↓** boucle entre le premier et le dernier élément. **B** ou **Échap** revient à l’écran précédent. L’élément sélectionné est encadré et éclairé ; le survol à la souris le sélectionne aussi. **Quitter** sur l’accueil, ainsi que **Recommencer** et **Menu principal** dans la pause d’un raid, se confirment en maintenant **A**, **Entrée** ou le clic pendant 0,8 s : une jauge se remplit dans le bouton et tout relâchement l’annule. Dans le **Hangar**, **A** ou un clic sur un avion le choisit et revient à l’accueil.

Une barre d’aide en bas de chaque écran rappelle les boutons utiles. Ses symboles suivent le dernier périphérique utilisé : touches du clavier, boutons Xbox, symboles PlayStation ou lettres Nintendo, selon le nom de la manette. Un clic sur une entrée de la barre déclenche l’action correspondante, sauf la validation. Maintenir une direction à la croix ou au stick répète le déplacement après 0,35 s, puis toutes les 0,08 s ; sur les curseurs de volume et de vibrations, le pas double après une seconde de maintien. Une direction déjà tenue à l’ouverture d’un écran ne se répète qu’après avoir été relâchée. De courts sons accompagnent les déplacements, les validations, les retours et les actions impossibles ; ils suivent le volume et la coupure du son. Dans **Réglages → Avancé**, maintenir **Réinitialiser le classement** rétablit les scores de départ et efface le record local et son rejeu.

## Deux joueurs

Les deux pilotes se relaient après chaque avion perdu. L’écran de ralliement affiche deux places : chaque joueur appuie sur **A** avec sa manette pour prendre la première place libre, et la manette vibre brièvement pour le confirmer. Au clavier, **Espace** ou **F** prend une place ; un clic sur une place libre la donne aussi au clavier. Une manette ne peut occuper qu’une place. **B** sur une manette déjà placée libère sa place, **Retour arrière** libère la dernière place du clavier, et **B** sur une autre manette ou **Échap** revient à l’accueil. Quand les deux places sont prises, **Start**, **Entrée** ou **Jouer** lance la partie.

Si les deux places sont au clavier, le joueur 1 pilote avec les flèches et **Espace**, le joueur 2 avec **W A S D** et **F**. Sinon, le joueur au clavier utilise les commandes des Réglages.

À chaque changement de pilote, seul le joueur attendu peut décoller avec **A** ou **Start** sur sa manette, ou **Entrée** s’il joue au clavier ; un appui sur une autre manette est refusé. À son premier tour, chaque joueur choisit son avion avec **LB / RB** ou **← / →** ; l’avion du premier joueur n’est pas proposé au second. Si la manette du joueur a été débranchée, un appui sur **A** avec une autre manette libre la remplace.

## Classement local

**Classement** affiche les 15 meilleurs scores. Le tableau de départ contient KRA (15 000), FFC (10 000), GRK (8 000) et GPT (5 000). En fin de raid manuel sans code, un score admissible permet de saisir trois lettres. Tape-les directement au clavier, ou choisis la lettre avec **↑ / ↓** et la position avec **← / →** au stick ou à la croix. À la manette, **A** passe à la lettre suivante et enregistre sur la troisième, **B** revient à la lettre précédente et, sur la première, passe la saisie. **Start** ou **Entrée** enregistre, **Échap** passe la saisie. À égalité, les scores déjà inscrits gardent leur place.

## Avion fantôme

Dans **Réglages → Avion fantôme**, choisis **Désactivé**, **Meilleur raid** ou **Dernier raid**. Le dernier raid terminé est utilisable même avec un score inférieur au record. La silhouette translucide suit le premier passage enregistré à la même distance, même si ta vitesse diffère. Elle s’efface près de ton avion et apparaît lorsque le rejeu sélectionné est disponible.

## Bilan du raid et records

Le bouton **Bilan par pont** compare le raid terminé au meilleur raid local pour chaque pont atteint. Il indique le temps et les points depuis le pont précédent, le carburant à l’arrivée et les avions perdus en route. **Voir** ouvre le rejeu correspondant à l’approche du pont. Dans le tableau, **↑ / ↓** défile d’une ligne et **LB / RB** ou **Page préc. / suiv.** avance ou recule d’un écran.

En fin de raid, le bilan affiche le score, la section atteinte et les ponts franchis, avec les records locaux de chaque statistique. Le bouton **A** de la manette valide **Rejouer** et **B** ramène au menu principal. **X** ouvre le bilan par pont et **Y** le classement, aussi avec les touches **X** et **Y** du clavier. Les records sont établis lors de raids manuels sans code.

## Langues

**Réglages → Jeu → Langue** permet de choisir l’une des treize langues avec **← / →** ; l’interface change de langue aussitôt. L’anglais est la langue par défaut. Chaque langue dispose de son propre fichier Gettext dans le dossier i18n, avec les mêmes identifiants de traduction.

## Réglages et record

Dans **Affichage**, **Afficher les FPS** indique en haut à droite le nombre d’images par seconde mesuré par le moteur. Le compteur est désactivé par défaut. Le réglage **Scanlines** applique à l’image du jeu des lignes **Légères**, **Moyennes** ou **Fortes**. L’effet est désactivé par défaut.

**Décor panoramique**, désactivé par défaut, prolonge les routes et le paysage sur les côtés en conservant le cadrage central et le HUD.

Chaque onglet présente une seule colonne de lignes. **← / →**, la croix ou le stick changent la valeur sur place ; **A**, **Entrée** ou un clic la font avancer d’un cran, et un clic sur **◀** la fait reculer. Une ligne d’explication sous la colonne décrit le réglage sélectionné. **B** ou **Échap** enregistre et revient à l’écran précédent.

Les onglets **Jeu**, **Commandes**, **Audio**, **Affichage** et **Avancé** se parcourent avec **LB / RB** à la manette, **Tab / Maj+Tab** et **Page préc. / suiv.** au clavier, ou d’un clic sur l’entrée **Onglet** de la barre d’aide. Sur la rangée d’onglets, **← / →** change aussi d’onglet.

Le menu **Réglages** est accessible depuis l’accueil et la pause ; depuis la pause, il ne montre que **Commandes**, **Audio** et **Affichage**. Il propose le plein écran, la cadence, la synchronisation, le rendu HD, la résolution adaptative et le volume.

- **Cadence Auto, 60, 75, 120 ou 144 Hz** choisit la cadence de rendu. Régler la fréquence physique de l’écran dans Windows. **Auto** suit la fréquence détectée, y compris après un changement d’écran.
- **Synchro Écran** synchronise la présentation sur la fréquence actuelle de l’écran. Choisir **Auto** pour une cadence régulière. Un plafond inférieur à la fréquence fixe de l’écran peut produire des répétitions d’images irrégulières.
- **Adaptative / VRR** limite le rendu à deux ou trois images/s sous la fréquence choisie, bornée par celle de l’écran. Activer le VRR dans Windows, le pilote et l’écran lorsqu’il est disponible. Le moteur Compatibility utilise la VSync classique comme limite supérieure. Le résultat VRR dépend du pilote, de l’écran et du mode d’affichage.
- **Synchro Off** utilise le plafond de cadence choisi. Le déchirement peut être visible.
- **Résolution adaptative** ajuste le nombre de pixels de la scène 3D selon le budget de temps entre les images et le temps GPU disponible. Elle peut réduire les ombres et l’anticrénelage pour tenir une cadence élevée. **Rendu HD** autorise une résolution maximale supérieure et l’anticrénelage aux cadences adaptées. Désactiver la résolution adaptative permet de conserver la qualité choisie.
- Le GPU effectue l’agrandissement bilinéaire avec un renforcement local de netteté. L’interface utilise la résolution de la fenêtre. **F1** affiche les images/s, la cible et la résolution 3D courante.

La simulation avance à 60 pas par seconde. La caméra, l’avion et le projectile sont interpolés entre les deux derniers états, avec au plus un pas de retard visuel. Les trajectoires des ennemis sont échantillonnées à la distance interpolée. Les rotors, les effets et l’inclinaison utilisent le temps de rendu. Le déplacement latéral affiché reconstitue la progression fractionnaire et résorbe progressivement les arrondis au relâchement. L’inclinaison suit la vitesse latérale. Cette correction visuelle peut produire un bref décalage avec la position de collision, inférieur à deux pixels natifs dans le test de changements rapides de direction.

Dans **Commandes**, la ligne **Périphérique** choisit d’afficher les touches du clavier ou les boutons de la manette ; elle part du dernier périphérique utilisé. Pour changer une commande, sélectionner sa ligne, puis appuyer sur sa nouvelle affectation dans les 5 secondes du décompte ; passé ce délai, l’affectation est annulée. **Rétablir les commandes** se confirme en maintenant **A**. Une affectation déjà utilisée est permutée avec l’ancienne. Le stick gauche conserve ses directions. **Échap** annule une affectation en cours. Les réglages sont enregistrés à la sortie de l’écran.

Le record local se met à jour à la fin d’un vol manuel. Les rejeux ne le modifient pas. Godot conserve les réglages et le record dans `user://fluvial_strike.cfg`.

## Vérification

Le rejeu de référence utilise les commandes de la fiche `../REFERENCE_GAMEPLAY.md`. Il dure 809 images. Il se termine en section 2 avec 930 points, 3 réserves, 50 847 unités de carburant et une abscisse native de 56. La suite compare aussi les images de chaque gain de score, la réponse latérale, le ravitaillement et les reprises des deux côtés du pont. Un second rejeu franchit dix ponts sans perte de réserve. La suite vérifie aussi des franchissements et reprises à des points de test répartis jusqu’au 2 000ᵉ pont.

Avec le binaire console de Godot, depuis ce dossier, exécuter la commande suivante. Le test renvoie un code d’erreur si une vérification échoue.

```powershell
godot --headless --path . --script res://verify.gd
```

Les données de vol sont incluses dans `course.gd`, `course_extension.gd`, `course_profiles.gd` et `course_blocks.bin`. Ce dernier contient les intervalles de rivière encodés par profil et les cibles extraites de la cartouche européenne. Le projet se lance avec Godot Standard, sans Blender, Stella, vidéo ni ROM.

## Export Windows

Dans l’éditeur Godot 4.7.2, installer le modèle Windows x86_64 dans le gestionnaire de modèles d’export. Puis choisir **Projet → Exporter → Windows x64** et exporter **Fluvial Strike.exe** en mode release. Distribuer l’exécutable avec le fichier `Fluvial Strike.pck`, le guide de lancement et les avis de licence fournis dans le ZIP de livraison.
