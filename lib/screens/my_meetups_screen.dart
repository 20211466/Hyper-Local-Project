import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../widgets/meetup_card.dart';
import '../widgets/manner_volt_dialog.dart';

class MyMeetupsScreen extends StatefulWidget {
  const MyMeetupsScreen({super.key});

  @override
  State<MyMeetupsScreen> createState() => _MyMeetupsScreenState();
}

class _MyMeetupsScreenState extends State<MyMeetupsScreen> {
  Widget _buildBadge(String text, MaterialColor color) {
    if (text == '비공개') return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[200]!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color[700],
        ),
      ),
    );
  }

  Widget _buildMannerVoltBadge(int volt) {
    String emoji;
    String title;
    MaterialColor color;

    if (volt < 30) {
      emoji = '🔋';
      title = '정전기';
      color = Colors.grey;
    } else if (volt < 100) {
      emoji = '💡';
      title = '꼬마전구';
      color = Colors.amber;
    } else if (volt < 300) {
      emoji = '⚡';
      title = '에너자이저';
      color = Colors.green;
    } else {
      emoji = '👑';
      title = '인간 발전소';
      color = Colors.purple;
    }

    return Container(
      margin: const EdgeInsets.only(top: 6, right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color[300]!, width: 1.5),
        boxShadow: volt >= 300
            ? [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '$volt V ($title)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color[800],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePicker(BuildContext context, User user) {
    final List<String> defaultAvatars = [
      'https://api.dicebear.com/8.x/micah/png?seed=Felix&backgroundColor=f4d150',
      'https://api.dicebear.com/8.x/micah/png?seed=Aneka&backgroundColor=b6e3f4',
      'https://api.dicebear.com/8.x/micah/png?seed=Tinkerbell&backgroundColor=c0aede',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Boo&backgroundColor=d1d4f9',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Max&backgroundColor=ffdfbf',
      'https://api.dicebear.com/8.x/avataaars/png?seed=Lola&backgroundColor=b6e3f4',
    ];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            '프로필 아바타 선택',
            style: TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: defaultAvatars.length,
              itemBuilder: (context, index) {
                final avatarUrl = defaultAvatars[index];
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    await user.updatePhotoURL(avatarUrl);
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .update({'photoUrl': avatarUrl});
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('프로필이 변경되었습니다! ✨')),
                      );
                      setState(() {});
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    ),
                    child: ClipOval(
                      child: Image.network(avatarUrl, fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  // 💡 [새로운 기능] 차단한 유저 목록을 보고 해제할 수 있는 팝업창
  void _showBlockedUsersDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '차단 관리',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());

                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;
                      final blockedUsers = List<String>.from(
                        data?['blockedUsers'] ?? [],
                      );

                      if (blockedUsers.isEmpty) {
                        return const Center(
                          child: Text(
                            '차단한 유저가 없습니다.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: blockedUsers.length,
                        itemBuilder: (context, index) {
                          final targetUid = blockedUsers[index];
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .doc(targetUid)
                                .get(),
                            builder: (context, targetSnapshot) {
                              if (!targetSnapshot.hasData)
                                return const SizedBox.shrink();

                              final targetData =
                                  targetSnapshot.data!.data()
                                      as Map<String, dynamic>?;
                              final name =
                                  targetData?['displayName'] ?? '알 수 없는 유저';
                              final photoUrl = targetData?['photoUrl'];

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green[50],
                                  backgroundImage: photoUrl != null
                                      ? NetworkImage(photoUrl)
                                      : null,
                                  child: photoUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.green,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    // 💡 DB의 배열에서 해당 유저 UID를 쏙 빼버립니다 (차단 해제)
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .update({
                                          'blockedUsers':
                                              FieldValue.arrayRemove([
                                                targetUid,
                                              ]),
                                        });
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '[$name]님의 차단을 해제했습니다.',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    '차단 해제',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '닫기',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 닉네임을 Firebase Authentication과 Firestore users 문서에 함께 저장합니다.
  Future<void> _showNicknameEditDialog(
    User user,
    String currentNickname,
  ) async {
    final controller = TextEditingController(text: currentNickname);

    final newNickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('닉네임 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: '새 닉네임',
            hintText: '닉네임을 입력하세요',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (newNickname == null) return;

    final trimmedNickname = newNickname.trim();
    if (trimmedNickname.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('닉네임을 입력해주세요.')));
      return;
    }

    try {
      // 앱 화면과 추천/채팅에서 사용하는 Firestore 프로필을 먼저 갱신합니다.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': trimmedNickname,
      }, SetOptions(merge: true));

      // 채팅 메시지 발신자 이름 등 Firebase Auth 프로필도 동일하게 맞춥니다.
      await user.updateDisplayName(trimmedNickname);
      await user.reload();

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('닉네임이 변경되었습니다.')));
    } catch (e) {
      debugPrint('[내 정보] 닉네임 변경 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('닉네임 변경에 실패했습니다: $e')));
    }
  }

  // 회원가입 때 저장한 카테고리 배열을 불러와 선택/삭제/순서 변경 후 저장합니다.
  Future<void> _showCategoryPreferenceEditor(
    BuildContext context,
    String uid,
    List<String> initialCategories,
  ) async {
    const List<String> categories = ['식사', '운동', '공부', '게임', '산책', '기타'];

    final selectedCategories = <String>[];
    for (final category in initialCategories) {
      if (categories.contains(category) &&
          !selectedCategories.contains(category)) {
        selectedCategories.add(category);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void toggleCategory(String category, bool selected) {
              setDialogState(() {
                if (selected) {
                  if (!selectedCategories.contains(category)) {
                    selectedCategories.add(category);
                  }
                } else {
                  selectedCategories.remove(category);
                }
              });
            }

            void moveCategory(int index, int direction) {
              final nextIndex = index + direction;
              if (nextIndex < 0 || nextIndex >= selectedCategories.length)
                return;

              setDialogState(() {
                final category = selectedCategories.removeAt(index);
                selectedCategories.insert(nextIndex, category);
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('관심 카테고리 설정'),
              content: SizedBox(
                width: double.maxFinite,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.62,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '관심 있는 카테고리를 선택하세요. 선택한 순서대로 모임 목록에 먼저 표시됩니다.',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          children: categories.map((category) {
                            final isSelected = selectedCategories.contains(
                              category,
                            );
                            return FilterChip(
                              label: Text(category),
                              selected: isSelected,
                              selectedColor: Colors.green.shade100,
                              checkmarkColor: Colors.green.shade800,
                              onSelected: (value) =>
                                  toggleCategory(category, value),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '추천 우선순위',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (selectedCategories.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '선택한 카테고리가 없습니다. 저장하면 전체 카테고리의 모임을 볼 수 있습니다.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          )
                        else
                          ...List.generate(selectedCategories.length, (index) {
                            final category = selectedCategories[index];
                            final isFirst = index == 0;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isFirst
                                    ? Colors.green.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isFirst
                                      ? Colors.green.shade200
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isFirst
                                        ? Colors.green
                                        : Colors.grey.shade500,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      category,
                                      style: TextStyle(
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
                                        : () => moveCategory(index, -1),
                                    icon: const Icon(Icons.keyboard_arrow_up),
                                  ),
                                  IconButton(
                                    tooltip: '아래로 이동',
                                    visualDensity: VisualDensity.compact,
                                    onPressed:
                                        index == selectedCategories.length - 1
                                        ? null
                                        : () => moveCategory(index, 1),
                                    icon: const Icon(Icons.keyboard_arrow_down),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .set({
                            'preferredCategories': List<String>.from(
                              selectedCategories,
                            ),
                          }, SetOptions(merge: true));

                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('관심 카테고리와 우선순위가 저장되었습니다.'),
                        ),
                      );
                    } catch (e) {
                      debugPrint('[내 정보] 관심 카테고리 저장 오류: $e');
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('관심 카테고리 저장에 실패했습니다: $e')),
                      );
                    }
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCategoryPreferenceSection(
    BuildContext context,
    String uid,
    List<String> preferredCategories,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.green, size: 19),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  '관심 카테고리 우선순위',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showCategoryPreferenceEditor(
                  context,
                  uid,
                  preferredCategories,
                ),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('편집'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.green.shade800,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          if (preferredCategories.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(
                '설정된 카테고리가 없습니다. 관심 카테고리를 설정하면 모임 목록에서 우선 추천됩니다.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(preferredCategories.length, (index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: index == 0 ? Colors.green : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: index == 0
                            ? Colors.green
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Text(
                      '${index + 1}순위 ${preferredCategories[index]}',
                      style: TextStyle(
                        color: index == 0
                            ? Colors.white
                            : Colors.green.shade800,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  // 💡 [회원 탈퇴] 1단계: 정말 탈퇴할 것인지 최종 확인
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '회원 탈퇴',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '정말 탈퇴하시겠어요?\n\n'
          '내가 만든 모임과 참여 기록, 매너 볼트, 프로필 정보가 모두 삭제되며 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '탈퇴하기',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await _performAccountDeletion(context);
  }

  // 💡 [회원 탈퇴] 2단계: 실제 삭제 실행. 재인증이 필요하면 재인증 흐름으로 넘어감
  Future<void> _performAccountDeletion(BuildContext context) async {
    final authService = AuthService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await authService.deleteAccount();
      if (context.mounted) Navigator.pop(context); // 로딩 닫기
      // 탈퇴 성공 시 AuthGate가 로그인 상태 변화를 감지해 자동으로 로그인 화면으로 전환합니다.
    } on FirebaseAuthException catch (e) {
      if (context.mounted) Navigator.pop(context); // 로딩 닫기
      if (e.code == 'requires-recent-login') {
        if (context.mounted)
          await _reauthenticateAndRetry(context, authService);
      } else if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authService.messageFor(e))));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다: $e')));
      }
    }
  }

  // 💡 [회원 탈퇴] 3단계: 오래된 로그인 세션일 때 본인 확인 후 탈퇴 재시도
  Future<void> _reauthenticateAndRetry(
    BuildContext context,
    AuthService authService,
  ) async {
    if (authService.isGoogleAccount) {
      try {
        await authService.reauthenticate();
        if (context.mounted) await _performAccountDeletion(context);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('재인증에 실패했습니다. 다시 시도해주세요.')),
          );
        }
      }
      return;
    }

    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('본인 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '보안을 위해 비밀번호를 다시 입력해주세요.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '비밀번호',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty || !context.mounted) return;

    try {
      await authService.reauthenticate(password: password);
      if (context.mounted) await _performAccountDeletion(context);
    } on FirebaseAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authService.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }

    final authService = AuthService();
    final firestore = FirebaseFirestore.instance;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '내 정보',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_off_outlined),
              tooltip: '차단 관리',
              onPressed: () => _showBlockedUsersDialog(context, user),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '로그아웃',
              onPressed: () => authService.signOut(),
            ),
            IconButton(
              icon: const Icon(
                Icons.no_accounts_outlined,
                color: Colors.redAccent,
              ),
              tooltip: '회원 탈퇴',
              onPressed: () => _confirmDeleteAccount(context),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.green,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.green,
            tabs: [
              Tab(text: '내가 만든 모임'),
              Tab(text: '참여한 모임'),
            ],
          ),
        ),
        body: Column(
          children: [
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: firestore.collection('users').doc(user.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('내 정보를 불러오지 못했습니다: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final userData = snapshot.data!.data() ?? <String, dynamic>{};
                final photoUrl = userData['photoUrl'] ?? user.photoURL;
                final ageGroup = (userData['ageGroup'] ?? '비공개').toString();
                final gender = (userData['gender'] ?? '비공개').toString();
                final mbti = (userData['mbti'] ?? '비공개').toString();
                final mannerVolt =
                    (userData['mannerVolt'] as num?)?.toInt() ?? 0;
                final nickname =
                    (userData['displayName'] ?? user.displayName ?? '닉네임 없음')
                        .toString();
                final rawPreferredCategories = userData['preferredCategories'];
                final preferredCategories = rawPreferredCategories is List
                    ? rawPreferredCategories.whereType<String>().toList()
                    : <String>[];

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => _showProfilePicker(context, user),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundColor: Colors.green[50],
                                  backgroundImage: photoUrl != null
                                      ? NetworkImage(photoUrl.toString())
                                      : null,
                                  child: photoUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.green,
                                          size: 34,
                                        )
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      size: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nickname,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '닉네임 변경',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Colors.green,
                                      ),
                                      onPressed: () => _showNicknameEditDialog(
                                        user,
                                        nickname,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.email ?? '',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _buildBadge(ageGroup, Colors.blue),
                                    _buildBadge(gender, Colors.pink),
                                    _buildBadge(mbti, Colors.purple),
                                    _buildMannerVoltBadge(mannerVolt),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle,
                                        color: Colors.orange,
                                        size: 20,
                                      ),
                                      tooltip: '테스트용 볼트 충전',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        try {
                                          await firestore
                                              .collection('users')
                                              .doc(user.uid)
                                              .update({
                                                'mannerVolt':
                                                    FieldValue.increment(10),
                                              });
                                        } catch (e) {
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('매너 볼트 변경 실패: $e'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildCategoryPreferenceSection(
                      context,
                      user.uid,
                      preferredCategories,
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 1, thickness: 1.5),
            Expanded(
              child: TabBarView(
                children: [
                  _MeetupStreamList(
                    stream: firestore
                        .collection('meetings')
                        .where('creatorId', isEqualTo: user.uid)
                        .snapshots(),
                    emptyMessage: '아직 만든 번개 모임이 없어요.\n지도에서 새로운 번개를 열어보세요!',
                    isCreatorMode: true,
                  ),
                  _MeetupStreamList(
                    stream: firestore
                        .collection('meetings')
                        .where('participants', arrayContains: user.uid)
                        .snapshots(),
                    emptyMessage: '아직 참여한 번개 모임이 없어요.\n지도에서 마음에 드는 번개에 참여해보세요!',
                    isCreatorMode: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetupStreamList extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final String emptyMessage;
  final bool isCreatorMode;

  const _MeetupStreamList({
    required this.stream,
    required this.emptyMessage,
    required this.isCreatorMode,
  });

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isMeetingEnded(Map<String, dynamic> data) {
    if (data['status'] == 'closed' || data['isClosed'] == true) return true;
    final deadline = _readDateTime(data['deadline']);
    return deadline != null && !deadline.isAfter(DateTime.now());
  }

  Future<void> _showMeetingManagementSheet(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MeetupManagementSheet(
        meetingId: docId,
        isCreator: (data['creatorId'] ?? '').toString() == uid,
      ),
    );
  }

  Future<void> _handleDeleteOrLeave(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isActuallyCreator = data['creatorId'] == uid;
    try {
      final meetingRef = FirebaseFirestore.instance
          .collection('meetings')
          .doc(docId);
      if (isActuallyCreator) {
        await meetingRef.delete();
        try {
          await ChatService().leaveRoom(docId);
        } catch (chatError) {
          debugPrint('[모임 삭제 후 채팅방 정리 실패] $chatError');
        }
      } else {
        await meetingRef.update({
          'participants': FieldValue.arrayRemove([uid]),
          'currentParticipants': FieldValue.increment(-1),
        });
        try {
          await ChatService().leaveRoom(docId);
        } catch (chatError) {
          debugPrint('[모임 나가기 후 채팅방 정리 실패] $chatError');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isActuallyCreator ? '모임을 삭제했습니다.' : '모임 기록에서 나갔습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('처리 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isActuallyCreator = data['creatorId'] == uid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isActuallyCreator ? '모임 삭제' : '모임 기록 삭제'),
        content: Text(
          isActuallyCreator
              ? '이 모임을 완전히 삭제할까요?\n참여자 평가를 먼저 진행하는 것을 권장합니다.'
              : '이 모임의 참여 기록을 내 목록에서 삭제할까요?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _handleDeleteOrLeave(context, docId, data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final docId = docs[index].id;
            final isEnded = _isMeetingEnded(data);
            final isCreator =
                data['creatorId'] == FirebaseAuth.instance.currentUser?.uid;

            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      _showMeetingManagementSheet(context, docId, data),
                  child: MeetupCard(meetupData: data),
                ),
                if (isEnded)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showDeleteDialog(context, docId, data),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isEnded && isCreator)
                  Positioned(
                    bottom: 20,
                    right: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '평가 가능',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MeetupManagementSheet extends StatefulWidget {
  final String meetingId;
  final bool isCreator;

  const _MeetupManagementSheet({
    required this.meetingId,
    required this.isCreator,
  });

  @override
  State<_MeetupManagementSheet> createState() => _MeetupManagementSheetState();
}

class _MeetupManagementSheetState extends State<_MeetupManagementSheet> {
  bool _isClosing = false;
  bool _isEvaluating = false;

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isEnded(Map<String, dynamic> data) {
    if (data['status'] == 'closed' || data['isClosed'] == true) return true;
    final deadline = _readDateTime(data['deadline']);
    return deadline != null && !deadline.isAfter(DateTime.now());
  }

  List<String> _participantIds(Map<String, dynamic> data) {
    final ids = <String>{};
    final creatorId = (data['creatorId'] ?? '').toString().trim();
    final raw = data['participants'];
    if (raw is Iterable) {
      for (final value in raw) {
        final id = value.toString().trim();
        if (id.isNotEmpty) ids.add(id);
      }
    }
    if (creatorId.isNotEmpty) {
      // 방장을 맨 앞에 노출하기 위해 별도 순서로 다시 구성합니다.
      return [creatorId, ...ids.where((id) => id != creatorId)];
    }
    return ids.toList();
  }

  Future<void> _closeMeetingEarly(Map<String, dynamic> data) async {
    if (!widget.isCreator || _isEnded(data) || _isClosing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('모임을 지금 마감할까요?'),
        content: const Text(
          '모임 모집이 즉시 종료됩니다.\n지도와 모임 탐색에서 더 이상 신규 참여자를 받지 않으며, 마감 후 참가자 평가를 진행할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('조기 마감'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClosing = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(widget.meetingId)
          .update({
            'deadline': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(seconds: 1)),
            ),
            'status': 'closed',
            'isClosed': true,
            'closedAt': FieldValue.serverTimestamp(),
            'closedBy': uid,
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('모임을 조기 마감했습니다. 이제 참가자 평가를 진행할 수 있습니다.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('모임 마감에 실패했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isClosing = false);
    }
  }

  Future<void> _startParticipantEvaluation(List<String> participantIds) async {
    if (_isEvaluating) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final targets = participantIds.where((id) => id != currentUid).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('평가할 다른 참여자가 없습니다.')));
      return;
    }

    // 평가창과 모임 상세창이 모두 닫힌 뒤에도 사용할 수 있도록 미리 가져옵니다.
    final messenger = ScaffoldMessenger.of(context);
    final sheetNavigator = Navigator.of(context);

    setState(() => _isEvaluating = true);
    try {
      final result = await showDialog<MannerVoltResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => MannerVoltDialog(
          participantIds: participantIds,
          meetingId: widget.meetingId,
        ),
      );

      if (!mounted || result == null) return;

      // 평가가 한 명에게도 반영되지 않았더라도, 최근 7일 이내 중복 평가
      // 결과를 안내해야 하므로 결과가 반환되면 상세창도 함께 닫습니다.
      final messages = <String>[];
      if (result.successCount > 0) {
        messages.add('${result.successCount}명의 매너 볼트 점수가 반영되었습니다.');
      }
      if (result.skippedCount > 0) {
        messages.add(
          '${result.skippedCount}명은 최근 7일 이내 이미 평가해 점수 반영에서 제외했습니다.',
        );
      }
      if (result.unavailableCount > 0) {
        messages.add(
          '${result.unavailableCount}명은 사용자 정보를 찾을 수 없어 평가하지 못했습니다.',
        );
      }
      if (messages.isEmpty) {
        messages.add('반영된 평가 점수가 없습니다.');
      }
      messages.add('종료된 모임 기록은 내 정보에 보관됩니다. 필요하면 목록에서 직접 삭제할 수 있습니다.');

      final message = messages.join('\n');
      final hasAppliedScore = result.successCount > 0;

      // 평가창은 이미 닫힌 상태입니다. 이제 모임 상세창을 닫고 안내문을 띄웁니다.
      sheetNavigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: hasAppliedScore
              ? Colors.green
              : Colors.orange.shade800,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = e.code == 'permission-denied'
          ? '평가 저장 권한이 없습니다. Firestore Rules가 최신 파일로 게시되었는지 확인해주세요.'
          : '평가 처리 중 오류가 발생했습니다. (${e.code})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('평가 처리 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isEvaluating = false);
    }
  }

  Widget _buildParticipantTile(String uid, String creatorId) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text('참여자 정보 불러오는 중...'),
          );
        }
        if (snapshot.hasError) {
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(uid == creatorId ? '방장' : '참여자'),
            subtitle: const Text('프로필을 불러오지 못했습니다.'),
          );
        }

        final userData = snapshot.data?.data() ?? <String, dynamic>{};
        final nickname = (userData['displayName'] ?? '이름 없는 사용자').toString();
        final photoUrl = (userData['photoUrl'] ?? '').toString();
        final mbti = (userData['mbti'] ?? '비공개').toString();
        final ageGroup = (userData['ageGroup'] ?? '비공개').toString();
        final gender = (userData['gender'] ?? '비공개').toString();
        final volt = (userData['mannerVolt'] as num?)?.toInt() ?? 0;
        final isHost = uid == creatorId;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade50,
            backgroundImage: photoUrl.isNotEmpty
                ? NetworkImage(photoUrl)
                : null,
            child: photoUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.green)
                : null,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '방장',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text('$ageGroup · $gender · $mbti · 매너 볼트 $volt V'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final meetingRef = FirebaseFirestore.instance
        .collection('meetings')
        .doc(widget.meetingId);
    final height = MediaQuery.of(context).size.height * 0.86;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: meetingRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('모임 정보를 불러오지 못했습니다: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.green),
            );
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('모임이 삭제되었거나 찾을 수 없습니다.'));
          }

          final title = (data['title'] ?? '제목 없음').toString();
          final category = (data['category'] ?? '기타').toString();
          final location =
              (data['location'] ?? data['dong'] ?? data['region'] ?? '장소 미상')
                  .toString();
          final creatorId = (data['creatorId'] ?? '').toString();
          final participants = _participantIds(data);
          final currentCount =
              (data['currentParticipants'] as num?)?.toInt() ??
              participants.length;
          final maxCount = (data['maxParticipants'] as num?)?.toInt() ?? 0;
          final ended = _isEnded(data);
          final deadline = _readDateTime(data['deadline']);

          return SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$category · $location',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ended ? Colors.grey.shade100 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        ended ? Icons.event_busy : Icons.groups,
                        color: ended ? Colors.grey : Colors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ended ? '종료된 모임' : '모임 참여 인원',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              maxCount > 0
                                  ? '$currentCount / $maxCount명 참여'
                                  : '$currentCount명 참여',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ended
                              ? Colors.grey.shade300
                              : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          ended ? '평가 단계' : '모집 중',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: ended
                                ? Colors.grey.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '참여자 정보',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${participants.length}명',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: participants.isEmpty
                      ? const Center(child: Text('등록된 참여자가 없습니다.'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          itemCount: participants.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) =>
                              _buildParticipantTile(
                                participants[index],
                                creatorId,
                              ),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.isCreator && !ended)
                        ElevatedButton.icon(
                          onPressed: _isClosing
                              ? null
                              : () => _closeMeetingEarly(data),
                          icon: _isClosing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.flag_rounded),
                          label: Text(_isClosing ? '마감 처리 중...' : '모임 조기 마감'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      if (widget.isCreator && !ended)
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Text(
                            '조기 마감하면 신규 참여가 중단되고 참가자 평가를 진행할 수 있습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      if (ended) ...[
                        ElevatedButton.icon(
                          onPressed: _isEvaluating || participants.length <= 1
                              ? null
                              : () => _startParticipantEvaluation(participants),
                          icon: _isEvaluating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.stars_rounded),
                          label: Text(
                            _isEvaluating ? '평가 화면 여는 중...' : '참가자 평가하기',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Text(
                            '평가를 마쳐도 모임 기록은 내 정보에 보관됩니다. 필요하면 목록의 휴지통 버튼으로 직접 삭제할 수 있습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      if (!ended && !widget.isCreator)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            '모임 방장이 마감하면 참가자 평가를 진행할 수 있습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (deadline != null && !ended)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '예정 마감: ${deadline.month}월 ${deadline.day}일 ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
