# 🔥 Votre Mac rame. Claude démasque le coupable.

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · **Français** · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Votre Mac s'étrangle → Claude nomme le processus exact qui le dévore → un clic le tue. Il n'agit jamais de lui-même.**

Toutes les heures, la charge de votre Mac part chez Claude. Il classe ce qui mange *vraiment* votre CPU/RAM, rédige la correction exacte et la dépose dans votre barre de menus — le pire en haut, codé par couleur, à un clic. Et avant que quoi que ce soit ne s'exécute, une *seconde* passe de Claude doit valider la commande comme **SAFE**.

**Mac Optimizing Looper** est une application de barre de menus macOS (sans icône dans le Dock) qui fait tourner une boucle continue **observer → interroger le modèle → conseiller → (éventuellement) agir** par-dessus votre CLI LLM local.

[**⬇ Installer**](#installation) · [**Voir en action ↓**](#comment-ça-marche)

<p align="center"><img src="docs/menu.png" alt="Menu de Mac Optimizing Looper — corrections classées et colorées par gravité" width="540"></p>

> Le Moniteur d'activité vous montre 200 lignes et zéro réponse. Ceci vous montre la **seule commande** qui règle le problème — et pourquoi.

## Comment ça marche

Un cycle, de haut en bas :

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

La barre de menus affiche le décompte. Le menu déroulant est classé **du pire au meilleur** : 🔴 critique → 🟡 avertissement → 🟢 hygiène. Chaque ligne se déplie en **Copier** · **Afficher dans le Terminal** · **Examiner avec Claude** · **Exécuter la commande maintenant**.

## Le garde-fou — pourquoi il ne fera pas exploser votre Mac

« Exécuter la commande maintenant » est le **seul** chemin qui exécute quoi que ce soit, et il est verrouillé de bout en bout :

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Tout ce qui n'est pas classé `SAFE` — **y compris `unknown`** — fait surgir une boîte de dialogue de confirmation dont le bouton par défaut est **Annuler**. Le conseil lui-même n'est qu'une donnée inerte ; le modèle ne peut jamais forcer l'application à exécuter quoi que ce soit. Ce contrat est verrouillé par `GuardrailTests`.

## Mac Optimizing Looper face aux suspects habituels

| | Moniteur d'activité | Applis « de nettoyage » | **Mac Optimizing Looper** |
|---|---|---|---|
| Trouve le vrai coupable | à vous de lire 200 lignes | devine | 🟢 Claude classe le pire en premier |
| Vous dit *pourquoi* ça rame | ✗ | ✗ | 🟢 une raison en langage clair |
| Donne la correction exacte | ✗ | un « nettoyage » générique | 🟢 la vraie commande `kill` / `unload` |
| Agit de lui-même | — | 🔴 oui, selon un planning | 🟢 jamais — uniquement sur votre clic |
| Garde-fou avant l'exécution | — | ✗ | 🟢 une seconde passe de Claude la valide `SAFE` |
| Où vont vos données | en local | ça dépend | uniquement vers votre propre CLI Claude |

## Installation

Nécessite le CLI `claude` dans votre PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> Le cask + le DMG seront disponibles après la première version signée. Le pipeline est en place et n'attend que les secrets de signature — voir [docs/release-setup.md](docs/release-setup.md). En attendant, compilez depuis les sources :

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Lancez le **bundle**, pas le binaire nu — `UNUserNotificationCenter` exige un véritable identifiant de bundle (`as.kargn.MacOptimizingLooper`).

## À votre goût

Choisissez **Provider / Model / Speed / Fast Mode** dans les Réglages — les modèles et les niveaux de raisonnement sont lus **en direct** depuis chaque CLI. Le backend par défaut est le CLI `claude` ; `codex` est aussi pris en charge (une seule passe contrainte par un schéma, sans étape de formatage distincte). L'interface est entièrement localisée en **10 langues**, et le sélecteur **Language** pilote à la fois l'interface *et* la langue de sortie de l'analyse.

<p align="center"><img src="docs/settings.png" alt="Réglages de Mac Optimizing Looper — fournisseur, modèle, langue, intervalle" width="520"></p>

## FAQ

**Est-ce qu'il exécute parfois quelque chose tout seul ?**
Non. Le conseil n'est qu'une donnée inerte. Le seul chemin d'exécution est le bouton « Exécuter la commande maintenant », sur votre clic — garanti par `GuardrailTests`.

**Est-ce sans danger d'appuyer sur « Exécuter » ?**
Chaque commande passe par une seconde passe de Claude. Tout ce qui n'est pas clairement `SAFE` (y compris `unknown`) fait surgir une boîte de confirmation dont le défaut est **Annuler**. `sudo` passe par l'invite de mot de passe graphique de macOS.

**Mes données quittent-elles mon Mac ?**
Uniquement les métriques en direct + la table des processus, et seulement vers Anthropic via *votre propre* CLI `claude` (ou OpenAI via `codex`) — exactement comme si vous utilisiez ce CLI vous-même. L'application n'ajoute aucune télémétrie.

**Combien ça coûte ?**
Rien de plus que votre usage existant du CLI `claude` / `codex`. L'application est gratuite et sous licence MIT.

**Pas de CLI `claude` installé ?**
Alors pas de conseil — l'application affiche l'erreur au lieu de deviner.

<details>
<summary><b>Sous le capot</b> — system prompt, cycle complet, flux de décision, configuration, limites</summary>

### System prompt (sanitized excerpt)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### Ce que chaque cycle peut toucher

| Étape | Outil | Effet de bord |
|---|---|---|
| Collecte | `MetricsCollector`, `mac-optimizer.sh` | lecture seule |
| Analyse | `claude -p` (effort = max) | réseau, lecture seule |
| Formatage | `claude -p` (effort = low) | JSON classé |
| Vérification du risque | `claude -p` | réseau, lecture seule |
| Exécution | `CommandExecutor` | **exécute la commande** (à l'initiative de l'utilisateur uniquement) |
| Examen | terminal configuré + `claude` interactif | ouvre un terminal |

### Flux de décision

```
timer → collect → claude analyze → rank suggestions
                                       │
                 user picks an action ─┼─ Copy / Show in Terminal → no execution
                                       ├─ Review with Claude       → interactive claude session
                                       └─ Run Command Now
                                              → claude risk-check
                                                   ├─ SAFE → run → notify → ✓
                                                   └─ else → confirm (default Cancel)
```

### Configuration

La configuration se trouve dans `~/.config/mac-optimizing-looper/config.json` (copiez `config.example.json`) : fournisseur, modèle, niveau de réflexion, secondes de surveillance, intervalle, terminal, langue. Elle est lue une seule fois au lancement — redémarrez après une modification manuelle.

### Limites / ce qu'elle refuse

- **N'agit jamais d'elle-même.** Seul « Exécuter la commande maintenant » exécute, et uniquement sur votre clic.
- **Risque inconnu = traité comme dangereux.** Sécurité par défaut ; c'est vous qui confirmez.
- **`sudo` → invite de mot de passe graphique.** Une exécution en arrière-plan n'a pas de TTY, donc les commandes root passent par `osascript … with administrator privileges`.
- **Pas de CLI `claude` = pas de conseil.** L'application affiche l'erreur au lieu de deviner.
- Les notifications nécessitent le bundle de l'application ; un binaire nu se rabat sur l'ouverture de la fenêtre de résultat.

</details>

---

Sous licence MIT. Conçu pour celles et ceux qui préfèrent savoir *pourquoi* leur Mac rame plutôt que de redémarrer en croisant les doigts.
