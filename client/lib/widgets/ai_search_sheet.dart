import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/poi_search_result.dart';
import '../theme/app_theme.dart';
import 'sheet_grab_handle.dart';

/// 자연어로 매장을 찾는 패널. 백엔드의 하이브리드 질의(`POST /query/ai`)를
/// 그대로 호출한다.
///
/// **대화형 생성 응답이 아니다.** 백엔드는 의미가 가장 가까운 매장 1건과 그
/// 층·입구 노드를 돌려주는 검색(retrieval)이라, 이 패널도 "질문에 문장으로
/// 답하는" RAG가 아니라 똑똑한 매장 찾기로 보이게 만든다. 예전에는 하드코딩된
/// 샘플 대화만 보여주는 껍데기였다.
class AiSearchSheet extends StatefulWidget {
  const AiSearchSheet({
    super.key,
    required this.buildingId,
    this.currentFloorId,
    this.initialQuery,
  });

  final String buildingId;

  /// 주면 그 층으로 스코프해서 찾는다. 층 라벨("B2")·내부 id 모두 허용된다.
  final String? currentFloorId;

  /// 열자마자 한 번 던질 질의. 검색 시트가 빈손으로 끝나 "AI 검색으로 찾기"로
  /// 넘어온 경우, 사용자가 방금 친 말을 다시 치게 하지 않는다.
  final String? initialQuery;

  /// 사용자가 결과를 골랐으면 그 매장을, 그냥 닫았으면 null을 돌려준다.
  static Future<PoiSearchResult?> show(
    BuildContext context, {
    required String buildingId,
    String? currentFloorId,
    String? initialQuery,
  }) {
    return showModalBottomSheet<PoiSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => AiSearchSheet(
        buildingId: buildingId,
        currentFloorId: currentFloorId,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  State<AiSearchSheet> createState() => _AiSearchSheetState();
}

/// 한 번의 질의와 그 결과. [result]는 찾은 매장(없으면 null)이고, [answer]는
/// 화면에 그대로 띄우는 문장이다.
class _Exchange {
  _Exchange(this.query);

  final String query;
  String? answer;
  PoiSearchResult? result;

  bool get pending => answer == null;
}

class _AiSearchSheetState extends State<AiSearchSheet> {
  final _controller = TextEditingController();
  final _exchanges = <_Exchange>[];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      // build 이후로 미뤄야 setState가 안전하다.
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit(initial));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final query = raw.trim();
    // 백엔드가 공백만 있는 질의를 422로 막으므로 아예 보내지 않는다.
    if (query.isEmpty || _busy) return;

    final exchange = _Exchange(query);
    setState(() {
      _exchanges.add(exchange);
      _busy = true;
      _controller.clear();
    });

    String answer;
    PoiSearchResult? result;
    try {
      final results = await destinationRepository.searchDestinationsAi(
        widget.buildingId,
        query,
        currentFloorId: widget.currentFloorId,
      );
      result = results.firstOrNull;
      if (result == null) {
        // status=no_match. 백엔드 임계값(0.50) 미달이거나 정말 없는 경우다.
        answer = '"$query"에 맞는 매장을 찾지 못했어요.';
      } else if (result.nodeId == null) {
        // status=ok_no_route — 위치는 알지만 입구 노드가 없어 경로 계산 불가.
        answer = '${result.name} · ${result.floor}에 있어요.\n'
            '(입구 정보가 없어 경로 안내는 어려워요)';
      } else {
        answer = '${result.name} · ${result.floor}에 있어요.';
      }
    } on Object {
      // 건물 없음(404)·검증 실패(422)는 repository가 빈 결과로 흡수하므로,
      // 여기 오는 건 서버 장애나 네트워크 끊김이다. 패널을 닫지 않고 안내만 한다.
      answer = '지금은 검색할 수 없어요. 잠시 후 다시 시도해 주세요.';
    }

    if (!mounted) return;
    setState(() {
      exchange.answer = answer;
      exchange.result = result;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // 키보드가 올라오면 입력창이 가려지지 않도록 그만큼 밀어 올린다.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabHandle(),
            _header(context),
            const Divider(height: 1),
            Flexible(child: _body(context)),
            _input(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 매장 찾기',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  '"밥 먹을 곳"처럼 편하게 물어보세요',
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.blue50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(32, 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_exchanges.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 28, 16, 28),
        child: Text(
          '찾고 싶은 곳을 자연어로 입력하면\n의미가 가장 가까운 매장을 알려드려요.',
          style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
        ),
      );
    }
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.7;
    return SingleChildScrollView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final exchange in _exchanges) ...[
            _bubble(
              text: exchange.query,
              maxWidth: maxBubbleWidth,
              fromUser: true,
            ),
            if (exchange.pending)
              _pendingBubble(maxBubbleWidth)
            else
              _bubble(
                text: exchange.answer!,
                maxWidth: maxBubbleWidth,
                fromUser: false,
                // 찾은 매장은 탭해서 그대로 매장 정보/길찾기 흐름으로 넘어간다.
                // 답만 보고 다시 검색창에 이름을 옮겨 적게 하지 않는다.
                onTap: exchange.result == null
                    ? null
                    : () => Navigator.of(context).pop(exchange.result),
              ),
          ],
        ],
      ),
    );
  }

  Widget _bubble({
    required String text,
    required double maxWidth,
    required bool fromUser,
    VoidCallback? onTap,
  }) {
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(fromUser ? 18 : 4),
      bottomRight: Radius.circular(fromUser ? 4 : 18),
    );
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: fromUser ? AppColors.indoor : AppColors.blue50,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      color: fromUser ? Colors.white : AppColors.text,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '눌러서 위치 보기',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 응답 대기 표시. 2차 의미 검색으로 넘어가면 백엔드가 임베딩 모델을
  /// 로드하느라 첫 질의가 수 초 걸릴 수 있어(CPU ~6초) 반드시 노출한다.
  Widget _pendingBubble(double maxWidth) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.blue50,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '찾는 중…',
              style: TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_busy,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                isDense: true,
                hintText: '예: 밥 먹을 곳',
                filled: true,
                fillColor: AppColors.blue50,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            // 응답을 기다리는 동안 중복 질의를 막는다.
            onPressed: _busy ? null : () => _submit(_controller.text),
            icon: const Icon(Icons.arrow_upward, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.indoor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(44, 44),
            ),
          ),
        ],
      ),
    );
  }
}
