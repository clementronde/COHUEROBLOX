# COHUE — Revues de sécurité, vague 2 (A11-05)

Agent A11, 5 nov. 2026. Checklist : `docs/security/regles-v2.md` §8. Base : `origin/main` = `851322e`. Branches lues après `git fetch` ; seules celles qui ont des commits au-dessus de main sont relues. Chaque branche a été compilée seule (`tools/check.sh`, worktree temporaire). Aucun test en Play (voir `tests-exploits.md`).

## Verdicts

| Branche | Commit relu | Ce qui change | Compile | Verdict |
| --- | --- | --- | --- | --- |
| `claude/a12-data-7c41` | `84b23d9` | Classements v2 « KO en une run », quarantaine, bannis ; S-06 et S-15 | 84 ok | **Fusionnable**, 3 remarques non bloquantes |
| `claude/a03-familles-comportements` | `03cbbaa` | Familles d'ennemis v2 (config, tirage des familles, invocations du boss) | 84 ok | **Fusionnable** |
| `claude/a05-compagnons` | `7fb2ca4` | Documentation seule (dossier 40, règles de capture et APIs) | — | **Conforme** aux règles §3 ; à revoir quand le code arrive |
| `claude/a10-son` | `d626883` | `SoundController` et `Config/Sounds` (client seulement) | 86 ok | **Fusionnable** |
| `claude/a14-armes-5c1460` | `f98bcef` | `WeaponFX` (client), scripts d'installation d'effets, Bloom | 83 ok | **Fusionnable** (aucun code serveur) |
| `claude/a11-failles` | — | Ma branche (S-11, S-16, docs) : à relire par le chef de projet | 84 ok | — |

Branches sans commit au-dessus de main : `a03-ennemis-2b1e1e`, `a06-movement-fff4cd`, `a09-lobby-9fc3de` (déjà fusionnées). Pas encore poussées : A02, A06 (validation), A13.

## `claude/a12-data-7c41` — fusionnable

| Point de la checklist | Résultat |
| --- | --- |
| Aucun `RemoteFunction` / `InvokeClient` | OK : aucun remote ajouté |
| Handlers C → S | Aucun nouveau |
| Aucun gain venu d'un argument client | OK : le score vient de `summary.kills` (résumé bâti par RunManager) et de `StatsService.getKills` ; borné à `MaxValue = 10 000 000` |
| Pas de `AssemblyLinearVelocity`, `FloorMaterial`, attribut client | OK |
| Classement écrit seulement par le serveur de run, en fin de run, avec relevé et quarantaine | OK : `scoreRun` une fois par run (fin, Cash out, départ en cours de run), relevé `boards.best` / `weekBest` dans le profil, quarantaine sur strikes ≥ 3 et invulnérabilité > 30 %, ban après 3 quarantaines en 7 jours (`RemoveAsync` des deux tableaux), bannis manuels filtrés à l'écriture et à la lecture. Studio, profil de test et magasin en mémoire n'écrivent jamais en ligne. Retardataires jamais classés (§5.5) |
| Un seul `mutate` avec clé d'idempotence | OK : `boards.lastRunKey = JobId:runId` vérifié et posé dans le même `mutate` |
| `ProcessReceipt` unique, pas de hasard payant | Non touché |
| Tables par `Player` vidées | OK : `lastWritten` supprimé (S-15) ; `DataService` n'écrit plus `lastSaveAt` pour une session partie (S-15) |
| Ancien profil sans les nouveaux champs | OK : `reconcile` remplit `boards.best`, `weekBest`, `quarantined` depuis `newProfile()` |

Remarques (non bloquantes, à suivre par A12 ou le chef de projet) :

1. **Invariants §2.2 inactifs** tant que `EnemyService.getRunSpawned` n'existe pas (le code le teste avec `safeCall`). À demander à A03 ou A04.
2. **Signaux encore en « log seul »** : `KoPerMinuteCap = 0` et `NoDamageEnforce = false`, comme le prévoit §0.6 (seuils non mesurés). Les mesurer en playtest (A13) puis les activer. La règle du joueur inactif (§4.3.3) et la fenêtre de score (`ScoreWindowOvertimeSeconds = 0`) attendent la décision de Clément.
3. **Petite fuite vers le tricheur** (§0.5) : une run en quarantaine ne met pas à jour `koRecord` dans le profil envoyé au client. Un tricheur attentif voit que son record perso n'a pas bougé. Acceptable aujourd'hui ; si on veut le cacher, afficher le meilleur entre `best` et le dernier relevé en quarantaine.

## `claude/a03-familles-comportements` — fusionnable

- `EnemyService.pickKind` : nouvelles familles (Support, Kamikaze) tirées par le serveur, tampons réutilisés ; aucune entrée client.
- `BossService` : l'invocation retombe sur `roster.Swarm` si le monde n'a ni `Armored` ni `Jumper` (pas de `spawnAt(nil)`).
- Aucun remote, aucun gain, pas de lecture de la position du client nouvelle. Les comportements Kamikaze et Support (dégâts aux joueurs) ne sont pas encore codés côté serveur : à relire quand ils arrivent (dégâts subis avec `RunManager.getDamageFeetY`, S-01).

## `claude/a05-compagnons` — conforme (documentation)

Le dossier 40 suit §3 : cage créée par le serveur seulement, aucun remote de capture, progression serveur avec joueur actif, hors choix de carte et sans nouveau strike, plafond de 5 par run, `grantCapture` dans un seul `mutate` avec `captureKey` dans le profil, refus si le profil n'est pas modifiable, Tamer lu côté serveur. Une cage commune avec une capture par joueur (ma recommandation §3.3).

À surveiller à la revue du code :

- le « touché même bloqué » dépend de `Bus.PlayerHit` (à fournir par RunManager) ; le repli `Bus.PlayerDamaged` laisse l'invulnérabilité aider à capturer (trou connu, documenté) ;
- le repli « collection en mémoire » ne doit tourner qu'en Studio ou sans A12, jamais en ligne.

## `claude/a10-son` — fusionnable

Client seulement. Le seul envoi au serveur est `UpdateSettings` (volumes), coupé par `Sounds.Volumes.Persist = false`. Le handler serveur rejette toute clé inconnue : rien à risquer. Avant de passer `Persist` à `true`, A12 doit ajouter `masterVolume`, `musicVolume`, `sfxVolume` (nombres finis bornés à 0..1) dans `onUpdateSettings`.

## `claude/a14-armes-5c1460` — fusionnable

`WeaponFX` (client) et des scripts d'installation à lancer en mode Edit. Aucun remote envoyé, aucun code serveur. La branche part d'une base plus ancienne (83 fichiers) : fusionner main dedans avant.
