# Pylos Ranks

<img src=".github/logo.png" width="96" align="right" alt="Pylos Ranks">

Replaces spells on your action bars with the highest rank you know. Learn Frostbolt Rank 3 and the bar button switches from Rank 2 on its own.

For WoW Forever (Interface 16001).

## Use

- **Left-click the minimap button** or type `/pranks`: check the bars now. The chat tells you how many spells were updated.
- **Right-click the button** or type `/pranks options`: open the options (in the game options under *AddOns*, *Pylos Ranks*).
- The button is gray while everything is up to date. It lights up and pulses when a lower rank sits on a bar.
- Nothing is replaced in combat. A check asked for during combat runs when it ends.

## When it checks

Switch each one on or off in the options:

| Option | Default | |
|---|---|---|
| New rank learned | on | after you learn a spell or rank |
| Action bar changed | off | when you drop a spell on a bar; a lower rank you place by hand is not replaced silently, you are asked: **Keep** puts it on the blacklist, **Replace** swaps it |
| Login and loading screen | off | at login, `/reload` and after every loading screen |

## Blacklist

Some players want a lower rank on purpose, for example to save mana. On the options page *Blacklist* click a spell in the list of known spells to put that rank on the blacklist; click it in the blacklist to take it off. Shift-click does this for all ranks of the spell. Pylos Ranks leaves blacklisted spells alone, says so in chat once, and can add a line to their spell tooltip (option *Hint in spell tooltip*, with a color of your choice).

The blacklist belongs to the character; the other options are shared by the account.

## Saved data

`PylosRanksDB` (account) and `PylosRanksCharDB` (blacklist, per character).

## License

GPL-3.0-or-later, see `LICENSE`. The addon ships no game data.
