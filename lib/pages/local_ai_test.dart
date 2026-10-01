
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/local_ai_service.dart';

class LocalAiTestPage extends StatefulWidget {
  const LocalAiTestPage({super.key});

  @override
  State<LocalAiTestPage> createState() => _LocalAiTestPageState();
}

class _LocalAiTestPageState extends State<LocalAiTestPage> {
  final LocalAiService _ai = LocalAiService.instance;

  final TextEditingController _messageController =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  String _status = 'Model not initialized.';
  double _progress = 0.0;

  bool _loading = false;
  bool _generating = false;

  // =====================================================
  // CHAT MESSAGE STORAGE
  // =====================================================

  final List<Map<String, String>> _messages = [];

  // =====================================================
  // COLORS
  // =====================================================

  Color _backgroundColor(bool isDarkMode) {
    return isDarkMode
        ? const Color(0xFF07111F)
        : const Color(0xFFF2F6FA);
  }

  Color _glassColor(bool isDarkMode) {
    return isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.65);
  }

  Color _borderColor(bool isDarkMode) {
    return isDarkMode
        ? Colors.white.withOpacity(0.12)
        : Colors.white.withOpacity(0.75);
  }

  Color _primaryTextColor(bool isDarkMode) {
    return isDarkMode
        ? Colors.white
        : const Color(0xFF17202A);
  }

  Color _secondaryTextColor(bool isDarkMode) {
    return isDarkMode
        ? Colors.white70
        : Colors.black54;
  }

  // =====================================================
  // INITIALIZE MODEL
  // =====================================================

  Future<void> _initializeModel() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _status = 'Preparing local AI...';
      _progress = 0.0;
    });

    try {
      await _ai.initialize(
        onDownloadProgress: (progress) {
          if (!mounted) return;

          setState(() {
            _progress = progress;
            _status =
                'Downloading model... ${(progress * 100).toStringAsFixed(1)}%';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _progress = 1.0;
        _status = 'Local AI model loaded.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _status = 'Error: $e';
      });
    }
  }

  // =====================================================
  // SEND MESSAGE
  // =====================================================

  Future<void> _sendMessage() async {
    if (!_ai.isInitialized || _generating) return;

    final message = _messageController.text.trim();

    if (message.isEmpty) return;

    _messageController.clear();

    // Add user's message immediately.
    setState(() {
      _messages.add({
        'role': 'user',
        'content': message,
      });

      // Add an empty assistant message that will be filled
      // as Gemma generates its response.
      _messages.add({
        'role': 'assistant',
        'content': '',
      });

      _generating = true;
      _status = 'AI is generating...';
    });

    _scrollToBottom();

    try {
      // =====================================================
      // BUILD CONVERSATION CONTEXT
      // =====================================================

      final StringBuffer conversation =
          StringBuffer();

      conversation.writeln(
        'Continue the conversation with the user.',
      );
      conversation.writeln();

      for (final chatMessage in _messages) {
        final role = chatMessage['role'];
        final content = chatMessage['content'] ?? '';

        // Do not include the currently empty assistant
        // response because Gemma needs to generate it.
        if (role == 'assistant' && content.isEmpty) {
          continue;
        }

        if (role == 'user') {
          conversation.writeln('User: $content');
        } else if (role == 'assistant') {
          conversation.writeln(
            'Assistant: $content',
          );
        }
      }

      conversation.writeln();
      conversation.writeln(
        'Assistant:',
      );

      // =====================================================
      // GENERATE RESPONSE
      // =====================================================

      await for (final token in _ai.ask(
        conversation.toString(),
      )) {
        if (!mounted) return;

        setState(() {
          _messages[_messages.length - 1]['content'] =
              '${_messages[_messages.length - 1]['content']}$token';
        });

        _scrollToBottom();
      }

      if (!mounted) return;

      setState(() {
        _generating = false;
        _status = 'Generation complete.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _generating = false;
        _status = 'Generation error: $e';

        // Remove the empty assistant message if
        // generation failed before producing anything.
        if (_messages.isNotEmpty &&
            _messages.last['role'] == 'assistant' &&
            (_messages.last['content'] ?? '').isEmpty) {
          _messages.removeLast();
        }
      });
    }

    _scrollToBottom();
  }

  // =====================================================
  // SCROLL TO BOTTOM
  // =====================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration:
            const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // =====================================================
  // MESSAGE BUBBLE
  // =====================================================

  Widget _buildMessageBubble({
    required BuildContext context,
    required String role,
    required String message,
    required bool isDarkMode,
  }) {
    final bool isUser = role == 'user';

    final Color textColor =
        _primaryTextColor(isDarkMode);

    return Align(
      alignment:
          isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
                  0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 55 : 0,
          right: isUser ? 0 : 55,
          bottom: 12,
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 12,
              sigmaY: 12,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? (isDarkMode
                        ? const Color(
                            0xFF2476D2,
                          ).withOpacity(0.70)
                        : const Color(
                            0xFF3D8FE5,
                          ).withOpacity(0.80))
                    : _glassColor(
                        isDarkMode,
                      ),
                borderRadius:
                    BorderRadius.circular(22),
                border: Border.all(
                  color: isUser
                      ? Colors.white.withOpacity(
                          0.15,
                        )
                      : _borderColor(
                          isDarkMode,
                        ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                      isDarkMode
                          ? 0.18
                          : 0.06,
                    ),
                    blurRadius: 12,
                    offset:
                        const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        isUser
                            ? Icons.person_outline
                            : Icons.smart_toy_outlined,
                        size: 16,
                        color: isUser
                            ? Colors.white70
                            : _secondaryTextColor(
                                isDarkMode,
                              ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isUser
                            ? 'You'
                            : 'DETECT-CO AI',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w600,
                          color: isUser
                              ? Colors.white70
                              : _secondaryTextColor(
                                  isDarkMode,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    message.isEmpty
                        ? '...'
                        : message,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.45,
                      color: isUser
                          ? Colors.white
                          : textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // CHAT LIST
  // =====================================================

  Widget _buildChatArea({
    required bool isDarkMode,
  }) {
    final Color primaryText =
        _primaryTextColor(isDarkMode);

    final Color secondaryText =
        _secondaryTextColor(isDarkMode);

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 35,
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 15,
                sigmaY: 15,
              ),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _glassColor(
                    isDarkMode,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    28,
                  ),
                  border: Border.all(
                    color: _borderColor(
                      isDarkMode,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 46,
                      color:
                          isDarkMode
                              ? Colors.white70
                              : const Color(
                                  0xFF3978A8,
                                ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'DETECT-CO AI',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ai.isInitialized
                          ? 'Ask me something about DETECT-CO, flood safety, preparedness, or other questions.'
                          : 'Load the local AI model first to start chatting.',
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color:
                            secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        16,
        18,
        16,
        18,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        return _buildMessageBubble(
          context: context,
          role: message['role'] ?? 'assistant',
          message: message['content'] ?? '',
          isDarkMode: isDarkMode,
        );
      },
    );
  }

  // =====================================================
  // MESSAGE INPUT
  // =====================================================

  Widget _buildMessageInput({
    required bool isDarkMode,
  }) {
    final bool modelReady =
        _ai.isInitialized;

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 15,
              sigmaY: 15,
            ),
            child: Container(
              padding:
                  const EdgeInsets.fromLTRB(
                6,
                6,
                6,
                6,
              ),
              decoration: BoxDecoration(
                color: _glassColor(
                  isDarkMode,
                ),
                borderRadius:
                    BorderRadius.circular(
                  28,
                ),
                border: Border.all(
                  color: _borderColor(
                    isDarkMode,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(
                      isDarkMode
                          ? 0.20
                          : 0.07,
                    ),
                    blurRadius: 15,
                    offset:
                        const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller:
                          _messageController,
                      enabled:
                          modelReady &&
                              !_generating,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction:
                          TextInputAction.newline,
                      style: TextStyle(
                        color:
                            _primaryTextColor(
                          isDarkMode,
                        ),
                        fontSize: 15,
                      ),
                      decoration:
                          InputDecoration(
                        hintText:
                            'Ask the local AI...',
                        hintStyle:
                            TextStyle(
                          color:
                              _secondaryTextColor(
                            isDarkMode,
                          ),
                        ),
                        filled: false,
                        border:
                            InputBorder.none,
                        contentPadding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!_generating) {
                          _sendMessage();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          modelReady &&
                                  !_generating
                              ? const Color(
                                  0xFF2476D2,
                                )
                              : Colors.grey
                                  .withOpacity(
                                  0.35,
                                ),
                    ),
                    child: IconButton(
                      onPressed:
                          (!modelReady ||
                                  _generating)
                              ? null
                              : _sendMessage,
                      icon:
                          _generating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                    color:
                                        Colors
                                            .white,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .arrow_upward_rounded,
                                  color:
                                      Colors.white,
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final bool modelReady =
        _ai.isInitialized;

    final bool isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    return Scaffold(
      backgroundColor:
          _backgroundColor(
        isDarkMode,
      ),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        backgroundColor:
            Colors.transparent,
        surfaceTintColor:
            Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glassColor(
                  isDarkMode,
                ),
                border: Border.all(
                  color: _borderColor(
                    isDarkMode,
                  ),
                ),
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 21,
                color:
                    _primaryTextColor(
                  isDarkMode,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Local AI'),
          ],
        ),
      ),
      body: Column(
        children: [
          // =====================================================
          // MODEL STATUS
          // =====================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              14,
              4,
              14,
              8,
            ),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 12,
                  sigmaY: 12,
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _glassColor(
                      isDarkMode,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                    border: Border.all(
                      color: _borderColor(
                        isDarkMode,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration:
                                BoxDecoration(
                              shape:
                                  BoxShape
                                      .circle,
                              color:
                                  modelReady
                                      ? Colors
                                          .green
                                      : Colors
                                          .orange,
                            ),
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          Expanded(
                            child: Text(
                              _status,
                              style:
                                  TextStyle(
                                fontSize: 13,
                                color:
                                    _secondaryTextColor(
                                  isDarkMode,
                                ),
                              ),
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                            ),
                          ),
                          if (!modelReady)
                            TextButton(
                              onPressed:
                                  _loading
                                      ? null
                                      : _initializeModel,
                              child:
                                  const Text(
                                'Load AI',
                              ),
                            ),
                        ],
                      ),
                      if (_loading) ...[
                        const SizedBox(
                          height: 7,
                        ),
                        LinearProgressIndicator(
                          value:
                              _progress > 0
                                  ? _progress
                                  : null,
                          minHeight: 3,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // =====================================================
          // CHAT
          // =====================================================

          Expanded(
            child: _buildChatArea(
              isDarkMode: isDarkMode,
            ),
          ),

          // =====================================================
          // INPUT
          // =====================================================

          _buildMessageInput(
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }
}
