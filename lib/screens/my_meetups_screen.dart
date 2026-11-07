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

  Future<void> _handleDeleteOrLeave(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isActuallyCreator = data['creatorId'] == uid;
    List<dynamic> participants = data['participants'] ?? [];

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          MannerVoltDialog(participantIds: participants, meetingId: docId),
    );

    if (shouldDelete != true) return;

    try {
      if (isActuallyCreator) {
        await FirebaseFirestore.instance
            .collection('meetings')
            .doc(docId)
            .delete();
        try {
          await ChatService().leaveRoom(docId);
        } catch (_) {}
      } else {
        await FirebaseFirestore.instance
            .collection('meetings')
            .doc(docId)
            .update({
              'participants': FieldValue.arrayRemove([uid]),
              'currentParticipants': FieldValue.increment(-1),
            });
        try {
          await ChatService().leaveRoom(docId);
        } catch (_) {}
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isActuallyCreator ? '종료된 모임을 삭제했습니다.' : '종료된 모임에서 나갔습니다.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리 중 오류가 발생했습니다.')));
      }
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isActuallyCreator = data['creatorId'] == uid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActuallyCreator ? '모임 삭제' : '모임 기록 삭제'),
        content: Text(
          isActuallyCreator
              ? '이 모임 데이터를 완전히 삭제하시겠습니까?\n(채팅방 목록에서도 사라집니다.)'
              : '이 모임의 참여 기록과 채팅방을 내 목록에서 지우시겠습니까?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleDeleteOrLeave(context, docId, data);
            },
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

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

        final now = DateTime.now();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final docId = docs[index].id;

            bool isExpired = false;
            if (data['deadline'] != null) {
              final deadline = (data['deadline'] as Timestamp).toDate();
              if (now.isAfter(deadline)) isExpired = true;
            }

            return Stack(
              children: [
                MeetupCard(meetupData: data),
                if (isExpired)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _showDeleteDialog(context, docId, data),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
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
              ],
            );
          },
        );
      },
    );
  }
}
