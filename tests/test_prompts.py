from invariant.cli.commands.initialize import _option_lines, _radio_select


OPTIONS = (
    ("first", "First choice", "The default choice."),
    ("second", "Second choice", "The alternate choice."),
)


def test_radio_options_are_unumbered_and_mark_only_the_selection() -> None:
    lines = _option_lines(OPTIONS, 1, "first")
    assert lines[0].startswith("  ○ First choice")
    assert lines[1].startswith("  ● Second choice")
    assert not any("1." in line or "2." in line for line in lines)


def test_radio_selector_uses_arrows_and_enter(capsys) -> None:
    keys = iter(("\x1b[B", "\r"))
    selected = _radio_select(OPTIONS, "first", key_reader=lambda: next(keys))
    assert selected == "second"
    output = capsys.readouterr().out
    assert "↑/↓ navigate • enter select" in output
    assert "\033[?25l" in output
    assert output.endswith("\033[?25h")
