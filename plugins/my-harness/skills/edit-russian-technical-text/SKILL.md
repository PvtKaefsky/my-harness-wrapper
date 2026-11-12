---
name: edit-russian-technical-text
description: Makes Russian technical prose clearer while keeping its meaning, terms and requirements. Use for Russian replies, Russian text the user gives to edit, Russian deliverables the user asked for, and Russian documentation in a project whose conventions use Russian.
---

# Edit Russian technical text

## Scope

This skill applies to four kinds of text:

- Russian replies;
- Russian text the user gives to edit;
- Russian deliverables the user asked for;
- Russian documentation in a project whose conventions use Russian.

It never moves an English artifact into Russian.

## Precedence

The session's own prose rules still apply to Russian text.
This skill adds only rules specific to Russian.
Where this skill and the session's instructions conflict, the instructions win.
Where this skill and the `humanizer` skill meet on Russian prose, this skill decides.

## Rules

| Rule | Before | After |
| --- | --- | --- |
| Replace a verbal noun or bureaucratic phrase with a verb. | Сервис осуществляет проверку токена. | Сервис проверяет токен. |
| Break a chain of genitives. | Проверка корректности заполнения полей формы. | Проверка того, правильно ли заполнены поля формы. |
| Use the active voice where an actor exists. | Агентом производится запуск сервиса. | Агент запускает сервис. |
| Drop empty words such as "данный", "является" and "на текущий момент". | Данный модуль на текущий момент является частью ядра. | Сейчас этот модуль входит в ядро. |
| Drop empty phrases such as "в рамках" and "в целях". | В рамках релиза в целях ускорения сборки включён кэш. | В релизе включён кэш, чтобы ускорить сборку. |
| Replace a calque from English with the native Russian phrase. | Резервная копия создаётся на ежедневной основе. | Резервная копия создаётся ежедневно. |
| Replace a slang anglicism with the standard Russian term where one exists. | Пофиксим тест, ревьюер заапрувит, и задеплоим. | Исправим тест, рецензент одобрит изменение, и развернём. |
| Keep an English term with no standard Russian equivalent, and every identifier, and format it as code. | Создайте ConfigMap с ключом timeout. | Создайте `ConfigMap` с ключом `timeout`. |
| Use one term per concept throughout the text. | Если узел не отвечает, оркестратор перезапускает хост. | Если узел не отвечает, оркестратор перезапускает этот узел. |

## Sentences that Russian joins with a dash

Russian grammar puts a dash (тире) between a noun subject and a noun predicate.
Where the session's instructions forbid dashes, rebuild such a sentence.
The rebuilt form uses a verb, a colon or a reordered clause.
In the examples below, "[тире]" marks where the dash would stand.

| Before | After |
| --- | --- |
| Python [тире] язык программирования. | Python относится к языкам программирования. |
| Задача [тире] обновить схему. | Задача: обновить схему. |

## What stays unchanged

Every technical term stays as written, except where the rules above replace a slang anglicism or unify two terms for one concept.
Every number stays as written.
Every condition stays as written.
Each requirement keeps its modality: "должен", "может" and "не должен" are never swapped, weakened or dropped.
The letter "ё" stays where the text has it and is not added where the text lacks it.
Russian angle quotes (ёлочки) stay where the text or the project uses them.
They are not converted to straight or curly quotes.

| Before | After |
| --- | --- |
| Осуществление повторной отправки запроса может производиться клиентом не более 3 раз. | Клиент может повторить запрос не более 3 раз. |
