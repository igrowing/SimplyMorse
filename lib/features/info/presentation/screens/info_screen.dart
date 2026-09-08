import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Educational reference: the full symbol table the app can
/// decode, Morse basics (timing and pauses), Farnsworth timing,
/// and common on-air abbreviations.
///
/// Read-only content, reachable from the info button in the app
/// bar on every main screen.
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(
        showSettingsIcon: false,
        titleText: 'Morse Code Guide',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle(context, 'Morse basics'),
              _buildBasicsChapter(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Pauses and timing'),
              _buildTimingChapter(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Farnsworth timing'),
              _buildFarnsworthChapter(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Symbols the app can decode'),
              _buildSymbolChapter(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Common abbreviations'),
              _buildAbbreviationChapter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSubsectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildParagraph(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        height: 1.4,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildChapter({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ── Chapter 1: Morse basics ───────────────────────────────

  Widget _buildBasicsChapter(BuildContext context) {
    return _buildChapter(
      context: context,
      children: [
        _buildParagraph(
          context,
          'Morse code is made of just two tones: the short dit '
          '(written as a dot ".") and the long dah (written as a '
          'dash "-"). A dah is exactly three times as long as a '
          'dit. Every letter, digit and punctuation mark is a '
          'unique sequence of dits and dahs.',
        ),
        _buildParagraph(
          context,
          'Speed is measured in words per minute (WPM) using the '
          'standard word "PARIS": one dit lasts 1200 / WPM '
          'milliseconds, so at 12 WPM a dit is 100 ms.',
        ),
      ],
    );
  }

  // ── Chapter 2: Pauses and timing ──────────────────────────

  Widget _buildTimingChapter(BuildContext context) {
    final rows = [
      ('Dit (dot)', '1 unit of tone'),
      ('Dah (dash)', '3 units of tone'),
      (
        'Pause between tones in a symbol',
        '1 unit of silence',
      ),
      ('Pause between symbols (letters)', '3 units of silence'),
      ('Pause between words', '7 units of silence'),
    ];
    return _buildChapter(
      context: context,
      children: [
        _buildParagraph(
          context,
          'The silences carry as much meaning as the tones. Three '
          'levels of pause separate elements, symbols and words:',
        ),
        _buildTwoColumnTable(context, rows),
      ],
    );
  }

  // ── Chapter 3: Farnsworth timing ──────────────────────────

  Widget _buildFarnsworthChapter(BuildContext context) {
    return _buildChapter(
      context: context,
      children: [
        _buildParagraph(
          context,
          'Farnsworth timing sends each character at full speed '
          'but stretches the pauses between characters and '
          'words, so the overall pace stays comfortable. You '
          'hear the true rhythm of each letter from the start '
          'and gain extra thinking time between them.',
        ),
        _buildParagraph(
          context,
          'It is the recommended way to learn: instead of slowing '
          'the characters down (which builds bad rhythm habits '
          'you must unlearn later), only the gaps grow.',
        ),
        _buildParagraph(
          context,
          'When Farnsworth timing is enabled in Settings, the app '
          'transmits at an effective speed of 10 WPM while the '
          'characters themselves keep your full WPM speed. The '
          'decoder recognizes both standard and Farnsworth '
          'timing automatically.',
        ),
      ],
    );
  }

  // ── Chapter 4: Symbol tables ──────────────────────────────

  Widget _buildSymbolChapter(BuildContext context) {
    return _buildChapter(
      context: context,
      children: [
        _buildSubsectionTitle(context, 'Letters'),
        _SymbolGrid(entries: MorseCodeTable.letters.entries),
        _buildSubsectionTitle(context, 'Digits'),
        _SymbolGrid(entries: MorseCodeTable.digits.entries),
        _buildSubsectionTitle(context, 'Punctuation'),
        _SymbolGrid(entries: MorseCodeTable.punctuation.entries),
        _buildSubsectionTitle(context, 'Prosigns'),
        _buildParagraph(
          context,
          'Prosigns are sent as one connected group, with no '
          'pauses between the letters.',
        ),
        _SymbolGrid(entries: MorseCodeTable.prosigns.entries),
        _buildSubsectionTitle(context, 'Latin Extended'),
        _buildParagraph(
          context,
          'European accented characters share short codes with '
          'ordinary letters, so they are decoded only when Latin '
          'Extended decoding is switched on.',
        ),
        _SymbolGrid(entries: MorseCodeTable.latinExtended.entries),
      ],
    );
  }

  // ── Chapter 5: Abbreviations ──────────────────────────────

  static const Map<String, String> _abbreviations = {
    '73': 'Best regards',
    '88': 'Love and kisses',
    'ABT': 'About',
    'AR': 'End of message (prosign, sounds like "di-dah-di-dah-dit")',
    'B4': 'Before',
    'BT':
        'Break between message parts (prosign, '
        'sounds like "dah-di-di-di-dah")',
    'C': 'Yes; correct; affirmative',
    'CL': 'Closing station; goodbye',
    'CQ': 'Calling any station',
    'CU': 'See you',
    'DE': 'From (this is ...)',
    'ES': 'And',
    'FB': 'Fine business; excellent',
    'GA': 'Good afternoon',
    'GE': 'Good evening',
    'GM': 'Good morning',
    'GN': 'Good night',
    'HI': 'Laughter',
    'HPE': 'Hope',
    'K': 'Go ahead; over',
    'KN': 'Go ahead, named station only',
    'N': 'No; negative',
    'NR': 'Number',
    'OK': 'All right; acknowledged',
    'OM': 'Old man; fellow operator',
    'OP': 'Operator',
    'PSE': 'Please',
    'R': 'Roger; received; understood',
    'SK': 'End of contact (prosign, sounds like "di-di-di-dah-dit")',
    'SOS': 'International distress signal',
    'TNX': 'Thanks (also TKS)',
    'UR': 'Your; you are',
    'WID': 'With',
    'WX': 'Weather',
    'YL': 'Young lady',
    'XYL': 'Wife ("ex-young lady")',
  };

  Widget _buildAbbreviationChapter(BuildContext context) {
    return _buildChapter(
      context: context,
      children: [
        _buildParagraph(
          context,
          'On the air, operators abbreviate constantly to keep '
          'transmissions short. The most common ones:',
        ),
        _buildTwoColumnTable(
          context,
          _abbreviations.entries.map((e) => (e.key, e.value)).toList(),
          header: ('Abbreviation', 'Meaning'),
        ),
      ],
    );
  }

  // ── Shared table builders ─────────────────────────────────

  Widget _buildTwoColumnTable(
    BuildContext context,
    List<(String, String)> rows, {
    (String, String)? header,
  }) {
    final theme = Theme.of(context);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(96),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(
        horizontalInside: BorderSide(color: theme.dividerColor),
      ),
      children: [
        if (header != null)
          TableRow(
            children: [
              _tableHeader(context, header.$1),
              _tableHeader(context, header.$2),
            ],
          ),
        for (final row in rows)
          TableRow(
            children: [
              _tableCell(
                context,
                row.$1,
                fontWeight: FontWeight.w600,
              ),
              _tableCell(context, row.$2),
            ],
          ),
      ],
    );
  }

  Widget _tableHeader(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _tableCell(
    BuildContext context,
    String text, {
    FontWeight? fontWeight,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: fontWeight,
        ),
      ),
    );
  }
}

/// Grid of character → code entries, laid out in two
/// character/code pairs per row.
class _SymbolGrid extends StatelessWidget {
  const _SymbolGrid({required this.entries});

  final Iterable<MapEntry<String, String>> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = entries.toList();
    const columns = 2;
    final rows = <Widget>[];

    for (var i = 0; i < list.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        final index = i + j;
        if (index < list.length) {
          cells.add(
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        list[index].key,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        list[index].value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          cells.add(const Expanded(child: SizedBox.shrink()));
        }
        if (j == 0) cells.add(const SizedBox(width: 16));
      }
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }
}
