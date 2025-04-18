# 📖 42_minishell_tester

## Sommaire

- [📖 42_minishell_tester](#-42_minishell_tester)
  - [Sommaire](#sommaire)
  - [Installation](#installation)
  - [Utilisation](#utilisation)
    - [Mode de test principal](#mode-de-test-principal)
    - [Filtres optionnels (pour modes `m` et `vm`)](#filtres-optionnels-pour-modes-m-et-vm)
  - [Installation et exécution](#installation-et-exécution)
  - [Journalisation des tests](#journalisation-des-tests)
  - [Mises à jour](#mises-à-jour)
  - [Avertissement](#avertissement)
  - [Contributeurs](#contributeurs)

---

## Installation

Commencez par commenter toutes les sorties vers le terminal dans votre minishell (par exemple les
`printf` de débogage ou l’affichage d’un message `exit`). Puis adaptez votre boucle principale pour
distinguer deux modes de lecture :

```c
if (isatty(fileno(stdin)))
    shell->prompt = readline(shell->terminal_prompt);
else {
    char *line = get_next_line(fileno(stdin));
    shell->prompt = ft_strtrim(line, "\n");
    free(line);
}
```

Cette modification permet au tester de fournir les commandes directement via l’entrée standard.

## Utilisation

Placez-vous à la racine de votre projet minishell, puis dans le dossier `42_minishell_tester`,
lancez :

```bash
bash tester.sh [m | vm | ne | d | b | a] [b | builtins] [pa | parsing] [r | redirections] [pi | pipelines] [c | cmds] [v | variables] [co | corrections] [path] [s | syntax]
```

### Mode de test principal

- `m` : tests obligatoires
- `vm` : tests obligatoires avec valgrind
- `ne` : tests sans environnement
- `d` : test de segfault (mode « brutal »)
- `b` : tests bonus
- `a` : tous les tests

### Filtres optionnels (pour modes `m` et `vm`)

- `b` ou `builtins` : tests sur les builtins
- `pa` ou `parsing` : tests de parsing
- `r` ou `redirections` : tests de redirections
- `pi` ou `pipelines` : tests de pipelines
- `c` ou `cmds` : tests de commandes
- `v` ou `variables` : tests de variables d’environnement
- `co` ou `corrections` : tests de corrections sujet
- `path` : tests de résolution de chemin
- `s` ou `syntax` : tests d’erreurs de syntaxe

## Installation et exécution

Pour installer le script automatiquement :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/RaphyStoll/42_minishell_tester/master/install.sh)"
```

Le tester sera installé dans `\$HOME/42_minishell_tester` et un alias `mstest` sera ajouté à votre
`.zshrc` ou `.bashrc`. Vous pourrez alors simplement faire :

```bash
mstest
```

## Journalisation des tests

Ce fork ajoute un système de **journalisation complète** des exécutions : tous les retours de vos
tests (STDOUT, STDERR, codes de sortie, fuites mémoire, etc.) sont automatiquement enregistrés dans
un dossier `mstest_log_<TIMESTAMP>` généré à chaque lancement :

- `init.log` : informations et contexte de démarrage (répertoires, utilisateur, etc.)
- `debug.log` : traces internes et étapes de traitement des tests
- `stdout.log` : sorties standard cumulées de tous les tests
- Dossiers `FALLBACK_<SECTION>` : logs détaillés (`.log`) par test pour chaque section
- `tests_sans_section` : tests pour lesquels la section n’a pas pu être déterminée
- `EMERGENCY_LOGS` : cas de log non créés dans leur dossier prévu

Vous pouvez également archiver automatiquement les anciens logs dans un sous‑dossier `archived_logs`
pour ne garder en racine que les éléments essentiels.

## Mises à jour

- Les tests sans environnement (`ne`) sont désormais séparés et mis à jour :
  ```bash
  bash tester.sh ne
  ```
- Toujours vérifier manuellement et ne pas vous fier uniquement au tester.

## Avertissement

- Ne pas pénaliser un candidat uniquement parce qu’il ne passe pas tous les tests ; inspectez le
  code.
- Ne pas valider quelqu’un uniquement parce que tous les tests passent ; revoyez les cas limites.
- Les vérifications de fuite de mémoire sont indicatives ; effectuez également vos propres tests.
- Si un test bloque en boucle, vous pouvez le commenter temporairement dans le fichier de test.

## Contributeurs

- Base initiale : [Tim](https://github.com/tjensen42) & [Hepple](https://github.com/hepple42)
- Améliorations : [Zsolt](https://github.com/zstenger93)
- Parsing hell & mini_death : [Kārlis](https://github.com/kvebers)
- Tests bonus : [Mouad](https://github.com/moabid42)
