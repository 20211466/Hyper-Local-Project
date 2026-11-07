
import 'package:flutter/material.dart';

/// 관심 카테고리 선택 및 우선순위 설정 위젯
class CategoryPreferenceSelector extends StatelessWidget {
  final List<String> selectedCategories;
  final ValueChanged<List<String>> onChanged;

  // 회원가입 화면은 다크 디자인이므로 true로 설정
  final bool darkMode;

  const CategoryPreferenceSelector({
    super.key,
    required this.selectedCategories,
    required this.onChanged,
    this.darkMode = false,
  });

  static const List<String> categories = [
    '식사',
    '운동',
    '공부',
    '게임',
    '산책',
    '기타',
  ];

  static const Color accentColor = Color(0xFFFF9955);

  void _toggleCategory(String category, bool selected) {
    final updated = List<String>.from(selectedCategories);

    if (selected) {
      if (!updated.contains(category)) {
        updated.add(category);
      }
    } else {
      updated.remove(category);
    }

    onChanged(updated);
  }

  void _moveCategory(int index, int direction) {
    final nextIndex = index + direction;

    if (nextIndex < 0 ||
        nextIndex >= selectedCategories.length) {
      return;
    }

    final updated = List<String>.from(selectedCategories);

    final item = updated.removeAt(index);
    updated.insert(nextIndex, item);

    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    final Color mainText =
        darkMode ? Colors.white : const Color(0xFF222222);

    final Color subText =
        darkMode ? Colors.white70 : Colors.black54;

    final Color borderColor =
        darkMode ? const Color(0xFF46505B) : Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '관심 카테고리',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: mainText,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          '관심 있는 카테고리를 선택하세요.\n선택한 순서대로 먼저 추천됩니다.',
          style: TextStyle(
            fontSize: 12,
            color: subText,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 14),

        // 카테고리 선택 영역
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: categories.map((category) {
            final bool isSelected =
                selectedCategories.contains(category);

            return FilterChip(
              label: Text(
                category,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected
                      ? accentColor
                      : mainText,
                ),
              ),
              selected: isSelected,

              backgroundColor: darkMode
                  ? const Color(0xFF29323D)
                  : Colors.grey.shade100,

              selectedColor: darkMode
                  ? const Color(0xFF493323)
                  : Colors.green.shade100,

              checkmarkColor: accentColor,

              side: BorderSide(
                color: isSelected
                    ? accentColor
                    : borderColor,
              ),

              onSelected: (value) {
                _toggleCategory(category, value);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        // 선택한 카테고리가 없는 경우
        if (selectedCategories.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: darkMode
                  ? const Color(0xFF29323D)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              '선택한 카테고리가 없습니다.\n관심 카테고리를 선택하면 해당 주제를 먼저 추천합니다.',
              style: TextStyle(
                fontSize: 12,
                color: subText,
                height: 1.5,
              ),
            ),
          )

        else ...[
          Text(
            '추천 우선순위',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: mainText,
            ),
          ),

          const SizedBox(height: 8),

          ...List.generate(selectedCategories.length, (index) {
            final String category =
                selectedCategories[index];

            final bool isFirst = index == 0;

            return Container(
              key: ValueKey('preference_$category'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: darkMode
                    ? (isFirst
                        ? const Color(0xFF493323)
                        : const Color(0xFF29323D))
                    : (isFirst
                        ? Colors.green.shade50
                        : Colors.grey.shade100),

                borderRadius: BorderRadius.circular(12),

                border: Border.all(
                  color: isFirst
                      ? accentColor
                      : borderColor,
                ),
              ),

              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: isFirst
                        ? accentColor
                        : Colors.grey.shade600,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      category,
                      style: TextStyle(
                        color: mainText,
                        fontSize: 14,
                        fontWeight: isFirst
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),

                  IconButton(
                    tooltip: '위로 이동',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == 0
                        ? null
                        : () => _moveCategory(index, -1),
                    icon: Icon(
                      Icons.keyboard_arrow_up,
                      color: index == 0
                          ? subText
                          : accentColor,
                    ),
                  ),

                  IconButton(
                    tooltip: '아래로 이동',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        index == selectedCategories.length - 1
                            ? null
                            : () => _moveCategory(index, 1),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color:
                          index == selectedCategories.length - 1
                              ? subText
                              : accentColor,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
