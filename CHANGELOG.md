# Changelog

## 1.1.0
- Pylos Core is no longer needed; you can remove it. The settings code now comes with the addon.
- The options page is now its own entry "Pylos Ranks" in the game's AddOns options (no longer below "Pylos").
- Your settings and the blacklist are kept.
- The minimap button no longer pulses for a slot the addon could not change.
- Clicking the button while you hold something on the cursor no longer says "0 spells updated."

## 1.0.2
- The question "keep the lower rank?" no longer counts as answered when the whole interface is hidden (Alt+Z) while it is open; it stays open and is asked again.
- Works with the new option pages of Pylos Core 1.0.1.

## 1.0.1
- Without Pylos Core the addon no longer causes a load error: it stays off and shows a chat line with a link to Pylos Core on CurseForge.
- Blacklist page: spells show without the rank, and the hint "Shift: all ranks" appears, only when a spell has several ranks in the book.

## 1.0.0
- First release. Replaces spells on the action bars with the highest known rank.
- Blacklist per character: spells on it stay unchanged (spell tooltip line, chat note "ignored").
- Checks on learning a spell, on moving a spell onto a bar (asks whether to keep a lower rank) and on login, each switchable; `/pranks` checks at once, `/pranks options` opens the options.
- A hint on the minimap button while an outdated rank is on a bar.
- Settings under "Pylos"; needs Pylos Core.
