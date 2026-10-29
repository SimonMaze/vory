---
name: vory-cards
description: Draw a native card inside a Vory chat by answering with a fenced a2ui block (A2UI v0.9 JSON). Use when the person needs to pick, confirm, or fill in a few fields — a form, a choice, a booking — and a button should send their answer back. Do not use it for approvals, secrets, or long documents.
---

# Native cards in Vory

Vory renders a fenced `a2ui` block in your reply as native controls (text, fields, choices, buttons). The person taps a button and Vory sends their answer back as the next user turn: a short sentence, then a fenced `a2ui-action` block. Read the sentence. The fence is the same action as JSON when you need the fields exactly.

One card is one surface. Put the whole surface in one fence. The root component's id is `root`.

## The fence

The block is a JSON array of A2UI v0.9 messages. `version` may be omitted; Vory fills in `v0.9`. A catalog id other than the basic catalog is read as the basic catalog. If you skip `createSurface`, Vory adds one.

```a2ui
[
  {"version":"v0.9","createSurface":{"surfaceId":"booking","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json","sendDataModel":true}},
  {"version":"v0.9","updateComponents":{"surfaceId":"booking","components":[
    {"id":"root","component":"Column","children":["title","day","go"]},
    {"id":"title","component":"Text","text":"When should we book","variant":"h4"},
    {"id":"day","component":"ChoicePicker","label":"Day","value":{"path":"/date"},"variant":"mutuallyExclusive","displayStyle":"chips","options":[{"label":"Tuesday","value":"Tuesday"},{"label":"Wednesday","value":"Wednesday"}]},
    {"id":"go","component":"Button","child":"goLabel","variant":"primary","action":{"event":{"name":"book","context":{"date":{"path":"/date"}}}}},
    {"id":"goLabel","component":"Text","text":"Book"}
  ]}},
  {"version":"v0.9","updateDataModel":{"surfaceId":"booking","value":{"date":["Tuesday"]}}}
]
```

Say in a sentence what the card is for, then the fence, then one line on what happens next. The card only appears once the fence has closed.

## What you can draw

Layout: `Column`, `Row`, `List`, `Card`, `Tabs`, `Divider`, `Modal`.
Content: `Text` (`text`, `variant` of `h1`–`h5`, `body`, `caption`), `Icon` (`name`), `Image`, `Video`, `AudioPlayer`.
Input: `TextField` (`label`, `value` as `{"path":"/field"}`), `CheckBox`, `ChoicePicker` (`label`, `options` of `{label, value}`, `value` path, `variant` of `mutuallyExclusive` or `multipleSelection`), `Slider`, `DateTimeInput`.
Action: `Button` (`child` is another component id, `variant` of `primary` or `default`, `action.event.name`, `action.event.context` of paths into the data model).

`Image`, `Video` and `AudioPlayer` `url` values load only over `https`. Anything else is dropped.

Set `sendDataModel` to true on `createSurface` when a button's context reads paths, and seed those paths with `updateDataModel`. A `ChoicePicker` value is an array, even for a single choice (`{"date":["Tuesday"]}`).

## What comes back

A tap sends a user message in two parts. First a sentence, for example: Chose "book" on the card: date Tuesday. Then a fenced `a2ui-action` block whose body is:

```json
{"version":"v0.9","action":{"name":"book","surfaceId":"booking","sourceComponentId":"go","timestamp":"…","context":{"date":["Tuesday"]}}}
```

Treat that as the person's answer. `action.name` is the button's event name. `action.context` holds the bound fields. Do not ask them to retype it. The card they already used shows as answered.

Do not put an approval, a password, or a secret in a card. Vory asks for those on its own cards, and a button here cannot answer them.
