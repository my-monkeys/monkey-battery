# CLAUDE.md — `monkey-battery`

App macOS de barre de menus : **dans combien de temps le Mac s'éteint**, et une alarme
impossible à rater dans les deux dernières minutes. Swift 6 / SwiftPM, macOS 14+, open source
(BSD-2), repo public `my-monkeys/monkey-battery`, cask `my-monkeys/tap/monkey-battery`.

Petite sœur de `monkey-claude-usage` : même palette, même chaîne de release (Sparkle,
notarisation locale, cask). `docs/RELEASING.md` fait foi pour la publication.

## Commandes

```bash
swift test                    # estimation, calibration, niveaux d'alerte, registre, traductions
swift build
./scripts/build-dmg.sh        # dist/Monkey Battery.app + dist/MonkeyBattery-<v>.dmg
./scripts/release.sh 0.1.0    # signe, notarise, tag, release GitHub, cask

"dist/Monkey Battery.app/Contents/MacOS/MonkeyBattery" --render-preview <dir>   # PNG de chaque état
"dist/Monkey Battery.app/Contents/MacOS/MonkeyBattery" --simulate [pourcentage] # décharge accélérée
```

Pas de linter : `swift build` doit sortir sans avertissement.

## D'où viennent les chiffres

Tout est lu dans l'entrée de registre `AppleSmartBattery` (ce qu'affiche
`ioreg -rn AppleSmartBattery`), **jamais** dans l'estimation de macOS : celle-ci est retenue
plusieurs minutes après le débranchement (« no estimate »), et son 0 % n'est pas le moment où
le Mac s'arrête. Pièges mesurés sur ce Mac (macOS 27) :

- ⚠️ **`AppleRawCurrentCapacity`, `AppleRawMaxCapacity` et `DesignCapacity` n'existent plus
  qu'à l'intérieur de `BatteryData`** ; les versions plus anciennes les mettaient à la racine.
  `BatterySample(registry:)` cherche aux deux endroits — les deux fixtures de test couvrent
  chacune une disposition.
- ⚠️ **Le courant arrive en non signé** quand il est négatif (ioreg affiche
  `18446744073709550168` pour −1448 mA). Lire le motif binaire : `Int64(truncatingIfNeeded:)`.
- ⚠️ **La jauge ne se rafraîchit que toutes les 20 à 60 s** (`UpdateTime`). Juste après le
  débranchement, elle renvoie encore le courant de charge, **positif**, pendant jusqu'à une
  minute. Juste après le branchement, l'inverse : encore négatif. `DrainEstimator` ignore une
  lecture dont l'`UpdateTime` n'a pas bougé, et une décharge antérieure au branchement.
- ⚠️ **Branché à 100 %, la batterie lit −34 mA** sans être en charge : c'est du maintien, pas
  un chargeur trop faible. D'où `pluggedDrainFloor` (−300 mA) : sur secteur, en dessous, ce
  n'est pas une décharge. Sans ce seuil, l'app affichait « 231h24 » et « chargeur trop faible ».
- Le pourcentage affiché par macOS n'est **pas** `raw / rawMax` (100 % pour 8241/8400 mAh).
  On le montre tel quel, mais le calcul se fait en mAh.

## L'estimation

`DrainEstimator` : moyenne exponentielle du courant, pondérée par le temps écoulé entre deux
mises à jour (constante de 180 s), puis charge projetée **depuis la dernière mise à jour** au
débit moyen — l'estimation est une **date** (`emptyAt`), pas une durée, pour que le compte à
rebours avance entre deux rafraîchissements de la jauge. Tout est arrondi **vers le bas**
(`TimeLeft`).

## Le seuil d'extinction s'apprend

Le Mac se met en veille **avant** que la jauge n'atteigne zéro, et Apple ne publie pas de
combien. Tant que rien n'a été observé : réserve prudente de **2 %** de la capacité (annoncer
la fin trop tôt coûte un peu de confiance, trop tard coûte le travail non enregistré).

À chaque tick sur batterie, un **battement** (`Heartbeat`) est écrit : dernière lecture + charge
projetée à cet instant. Il est sauvé à **chaque tick** dès le niveau `.low`, pour survivre à
l'extinction. Au relancement ou au réveil, `ShutdownCalibration` le reprend : s'il date de
**≥ 120 s**, à **≤ 1 %** ou avec `AtCriticalLevel`, et que la charge n'a pas continué de
baisser sans l'app, c'était l'extinction → la charge projetée devient le seuil (médiane des 5
dernières). Un couvercle fermé à 5 % n'est **pas** compté. Le journal vit dans
`~/Library/Application Support/fr.mymonkey.monkeybattery/journal.json`.

La simulation utilise un journal **en mémoire** : elle ne doit pas apprendre un faux seuil.

## Niveaux d'alerte

Pilotés par le **temps restant**, le pourcentage ne servant que de filet tant qu'il n'y a pas
d'estimation : 1 % dure de deux à six minutes selon la charge.

| Niveau | Seuil | Effet |
|---|---|---|
| `low` | ≤ 10 % (réglable) | l'icône apparaît avec le temps restant |
| `warning` | ≤ 5 min ou ≤ 3 % | une notification + son « Glass » |
| `critical` | ≤ 2 min ou ≤ 1 % | panneau rouge + alarme « Sosumi » toutes les 15 s |
| `final` | ≤ 30 s ou `AtCriticalLevel` | panneau réaffiché même masqué, alarme toutes les 5 s |

**Le niveau ne redescend pas pendant une décharge** (`AlertEscalation`) : une estimation qui
remonte d'une minute parce qu'une vidéo est en pause ne retire pas l'alerte. Il retombe dès que
la batterie ne se vide plus — et `PowerSourceObserver` (notification IOPS) relit la batterie
**à l'instant** du branchement, sans attendre la jauge : le panneau disparaît tout de suite.

Le panneau (`AlertPanel.swift`) est un `NSPanel` **non activant** au niveau `.screenSaver`, sur
tous les Spaces et par-dessus les apps plein écran. Non activant : il ne vole pas le clavier,
un Retour tapé dans un document ne déclenche pas son bouton. Une notification seule ne suffit
pas — c'est ce qu'on rate aujourd'hui (bannière de 5 s, mode Concentration, et le type
d'alerte qui passe outre est réservé par Apple).

## ⚠️ L'icône : masquer sans perdre sa place

macOS ajoute toute nouvelle icône **à gauche** de toutes les autres, et aucune API ne permet de
choisir sa place. L'utilisateur la ⌘-glisse à côté de la batterie ; macOS retient la position
sous `NSStatusItem Preferred Position MonkeyBattery` (domaine de l'app) grâce à
`autosaveName`. Deux pièges vérifiés :

- **`isVisible = false` efface cette position** (la clé disparaît des préférences) et écrit
  `NSStatusItem VisibleCC MonkeyBattery = 0`, que macOS 26+ traite comme un retrait par
  l'utilisateur. L'icône masquée est donc réduite à **`length = 0`**, jamais retirée.
- Écrire soi-même la position avant le lancement **n'est pas honoré** : on ne peut pas placer
  l'icône d'office à côté de la batterie (dont la position est dans `com.apple.controlcenter`).

D'où la **fenêtre de placement** : l'icône reste visible 60 s après chaque lancement ou
réouverture (Spotlight, Launchpad), le temps du ⌘-glisser. Ne pas changer `autosaveName` :
chaque utilisateur perdrait sa place.

## Build et release

- ⚠️ **Avec Swift 6.4 (backend swift-build), le build universel pose `Sparkle.framework` à
  côté de l'exécutable**, plus dans `Frameworks/`. `build-app.sh` cherche aux deux endroits.
- L'app s'ajoute **une fois** aux éléments de connexion, et seulement depuis `/Applications`
  (un build de `dist/` enregistré resterait accroché). Les Réglages le défont.
- Clé Sparkle au compte **`monkey-battery`** du trousseau (clé publique
  `GyWMgK03BiVL4R9ap8U+pYzc/Brj8e0wDKk7cs/STdo=`). Le premier `sign_update` ouvre une
  fenêtre du trousseau et **bloque `release.sh` sans message** : « Toujours autoriser ».
- Commits sur ce repo public : auteur `MaximCosta` (noreply), **aucune mention d'IA**.
