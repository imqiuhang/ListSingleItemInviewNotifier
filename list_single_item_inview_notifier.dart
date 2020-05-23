import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
***************  使用 详见 list_single_item_inview_notifier_test  *********
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*/

class ListSingleItemInviewNotifier extends StatefulWidget {
  /*ListView或者其他都OK，但如果子Widget如果嵌套了NotificationListener
  必须确保收到ScrollNotification不能被独占，需返回false*/
  final Widget child;

  // @request 用于ListView的item计算需要的，必须确保和需要计算的ListView传入同一个scrollController
  final ScrollController scrollController;

  // 如果在listView数据刷新后需要更新inview的则传入，在数据刷新后调用inviewController.listViewDataDidRead()
  final ListSingleItemInviewController inviewController;

  /*当前需要被计算的item的缓存个数，
  一般设置为ListView两个屏幕能塞下的item的大致个数就行，
  超出屏幕了还去计算比较浪费资源
  default is 20 */
  final int calculateCacheCount;

  // 需要监听的主列表的滑动方向，用于计算item的starPosition及滚动方向上的尺寸
  final Axis scrollDirection;

  /// 计算item是否inView的简单计算方式
  final IsInViewExposeRatioCondition isInViewExposeRatioCondition;

  /// 自定义计算item是inView的完全自定义计算方式
  final IsInViewCustomerCondition isInViewCustomerCondition;

  //是否按照item的index来寻找第一个符合条件的item，false的话按照加入item的顺序查找
  final bool findDependItemIndex;

  const ListSingleItemInviewNotifier({
    Key key,
    this.child,
    @required this.scrollController,
    this.inviewController,
    this.calculateCacheCount = 20,
    this.scrollDirection = Axis.vertical,
    this.findDependItemIndex = true,
    // 默认是item自尺寸1/2进入listView可视范围，且 1/2以内的尺寸超出可视范围
    this.isInViewExposeRatioCondition = const IsInViewExposeRatioCondition(
        minEnterRatio: 0.5, maxOverRatio: 0.5),
    this.isInViewCustomerCondition,
  })  : assert(calculateCacheCount >= 1),
        assert(isInViewExposeRatioCondition != null ||
            isInViewCustomerCondition != null),
        assert(findDependItemIndex != null),
        assert(scrollController != null),
        super(key: key);

  @override
  _ListSingleItemInviewNotifierState createState() =>
      _ListSingleItemInviewNotifierState();

  /// 列表里的子widget可以通过该方法在widget树里找到InViewState
  static InViewState of(BuildContext context) {
    final InheritedElement inheritedElement = context
        .getElementForInheritedWidgetOfExactType<_InheritedInViewWidget>();
    final _InheritedInViewWidget widget = inheritedElement?.widget;
    return widget?.inViewState;
  }
}

class _ListSingleItemInviewNotifierState
    extends State<ListSingleItemInviewNotifier> {
  InViewState _inViewState;
  StreamController<ScrollNotification> _streamController;

  @override
  void initState() {
    super.initState();

    _inViewState = InViewState(
        scrollDirection: widget.scrollDirection,
        calculateCacheCount: widget.calculateCacheCount,
        isInViewCustomerCondition: widget.isInViewCustomerCondition,
        isInViewExposeRatioCondition: widget.isInViewExposeRatioCondition,
        findDependItemIndex: widget.findDependItemIndex,
        scrollController: widget.scrollController,
        inviewController: widget.inviewController,
        cacheContent: widget.inviewController._cachedContents);
    widget.inviewController._inViewStateCache = _inViewState;
    widget.inviewController._cachedContents = _inViewState._cachedContents;
    _streamController = StreamController<ScrollNotification>();
    _streamController.stream.listen(_inViewState._onScrollNotification);
  }

  @override
  void dispose() {
    widget.inviewController._inViewStateCache = null;
    _inViewState?.dispose();
    _inViewState = null;
    _streamController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // InheritedInViewWidget能通过of context 拿到inViewStatus
    return _InheritedInViewWidget(
      inViewState: _inViewState,
      child: NotificationListener<ScrollNotification>(
        child: widget.child,
        onNotification: (ScrollNotification notification) {
          if (_streamController != null && !_streamController.isClosed) {
            _streamController.add(notification);
          }
          return false;
        },
      ),
    );
  }
}

class InViewState extends ChangeNotifier {
  List<_WidgetContextData> _cachedContents;
  BuildContext currentInViewItemContext;

  final int calculateCacheCount;
  final Axis scrollDirection;
  final IsInViewExposeRatioCondition isInViewExposeRatioCondition;
  final IsInViewCustomerCondition isInViewCustomerCondition;
  final bool findDependItemIndex;
  final ScrollController scrollController;
  final ListSingleItemInviewController inviewController;
  bool forceIgnoreAllInViewItem = false;

  InViewState(
      {@required this.scrollDirection,
      @required this.scrollController,
      @required this.calculateCacheCount,
      @required this.isInViewExposeRatioCondition,
      @required this.isInViewCustomerCondition,
      @required this.findDependItemIndex,
      List<_WidgetContextData> cacheContent,
      this.inviewController})
      : _cachedContents = cacheContent ?? List(),
        forceIgnoreAllInViewItem =
            (inviewController?.forceIgnoreAllInViewItem) ?? false;

  void addContext({@required BuildContext context, @required int index}) {
    if (context == null) {
      return;
    }
    bool needUpdate = (_getListLength(_cachedContents) == 0);

    _cachedContents.removeWhere((d) => d.context == context);
    _cachedContents.add(_WidgetContextData(context: context, index: index));
    if (_cachedContents.length > calculateCacheCount) {
      _cachedContents.removeAt(0);
    }

    if (findDependItemIndex) {
      _cachedContents.sort((_WidgetContextData a, _WidgetContextData b) =>
          _nonnullIntFromInt(a.index).compareTo(_nonnullIntFromInt(b.index)));
    }

    if (needUpdate) {
      ScrollPosition scrollPosition;
      try {
        scrollPosition = scrollController.position;
      } catch (e) {}

      // 为了第一次加载数据的时候能自动刷新一下 因为这个时候用户没有滑动过
      // 当用户滑动过以后就不用自动刷新了，半个屏幕的判断其实就是为了防一下下拉刷新的offset
      if (scrollPosition != null &&
          scrollPosition.pixels != null &&
          scrollPosition.viewportDimension != null &&
          scrollPosition.pixels <= scrollPosition.viewportDimension / 2) {
        _updateInViewItem();
      }
    }
  }

  void removeContext({@required BuildContext context}) {
    if (context != null) {
      _cachedContents.removeWhere((d) => d.context == context);
    }
  }

  bool isCurrentInViewItemWithContext({@required BuildContext context}) {
    return !forceIgnoreAllInViewItem &&
        context != null &&
        currentInViewItemContext == context;
  }

  int get currentCacheCount => (_getListLength(_cachedContents));

  void _onScrollNotification(ScrollNotification notification) {
    if (notification == null || !(notification is ScrollEndNotification)) {
      return;
    }
    _updateInViewItem();
  }

  void _onForceIgnoreAllInViewItemOptionChanged(bool option) {
    if (forceIgnoreAllInViewItem != option) {
      forceIgnoreAllInViewItem = option;
      notifyListeners();
    }
  }

  void _updateInViewItem() {
    if (scrollController == null) {
      return;
    }

    BuildContext findFirstInViewItemId;

    ScrollPosition scrollPosition;
    try {
      scrollPosition = scrollController.position;
    } catch (e) {}

    if (scrollPosition == null) {
      return;
    }

    final double listContentDimension = scrollPosition.viewportDimension;

    final double pixels = scrollPosition.pixels;

    if (listContentDimension == null || pixels == null) {
      return;
    }

    for (_WidgetContextData item in _cachedContents) {
      final RenderObject renderObject = item?.context?.findRenderObject();

      if (renderObject == null ||
          !renderObject.attached ||
          item.context == null) {
        continue;
      }

      final RenderAbstractViewport viewport =
          RenderAbstractViewport.of(renderObject);

      final RevealedOffset listOffset =
          viewport?.getOffsetToReveal(renderObject, 0.0);

      final Size itemSize = renderObject?.semanticBounds?.size;

      if (listOffset == null || itemSize == null) {
        continue;
      }

      final double itemStarPoint = listOffset.offset - pixels;
      double directionItemSize = (scrollDirection == Axis.horizontal)
          ? itemSize.width
          : itemSize.height;

      final double itemEndPoint = itemStarPoint + directionItemSize;

      bool isItemInViewport = false;

      if (isInViewCustomerCondition != null) {
        isItemInViewport = isInViewCustomerCondition(itemStarPoint,
            itemEndPoint, listContentDimension, itemSize, item.context);
      } else if (isInViewExposeRatioCondition != null) {
        isItemInViewport = _isInViewDefaultCalculate(
            itemStarPoint,
            itemEndPoint,
            listContentDimension,
            directionItemSize,
            item.context);
      }

      if (isItemInViewport) {
        /// 如果当前的item仍然inView，那么寻找结束，什么都不用做
        if (isCurrentInViewItemWithContext(context: item.context)) {
          findFirstInViewItemId = item.context;
          break;
        }

        // 如果没找到当前的item，那么一直找到最后一个，如果后面没有当前的item，那么就取第一个
        if (findFirstInViewItemId == null) {
          findFirstInViewItemId = item.context;
        }
      }
    }

    bool needNotify = true;
    if (currentInViewItemContext == null && findFirstInViewItemId == null) {
      needNotify = false;
    } else if (currentInViewItemContext == findFirstInViewItemId) {
      needNotify = false;
    }

    currentInViewItemContext = findFirstInViewItemId;

    if (needNotify) {
      notifyListeners();
    }
  }

  bool _isInViewDefaultCalculate(double itemStarPoint, double itemEndPoint,
      double listContentDimension, double directionSize, BuildContext context) {
    if (isInViewExposeRatioCondition == null ||
        isInViewExposeRatioCondition.minEnterRatio == null ||
        isInViewExposeRatioCondition.minEnterRatio == null ||
        scrollDirection == null ||
        itemEndPoint == null ||
        listContentDimension == null ||
        directionSize == null ||
        context == null) {
      return false;
    }

    double minStartSize =
        directionSize * isInViewExposeRatioCondition.minEnterRatio;
    double maxOverSize =
        directionSize * isInViewExposeRatioCondition.maxOverRatio;

    return (itemEndPoint >= minStartSize &&
        itemEndPoint <= (listContentDimension + maxOverSize));
  }
}

class _InheritedInViewWidget extends InheritedWidget {
  final InViewState inViewState;
  final Widget child;

  _InheritedInViewWidget({Key key, this.inViewState, this.child})
      : super(key: key, child: child);

  @override
  bool updateShouldNotify(_InheritedInViewWidget oldWidget) => false;
}

class _WidgetContextData {
  final BuildContext context;

//  final String id;
  final int index;

  _WidgetContextData({@required this.context, @required this.index});
}

class IsInViewExposeRatioCondition {
  const IsInViewExposeRatioCondition(
      {@required this.minEnterRatio, @required this.maxOverRatio})
      : assert(minEnterRatio != null && maxOverRatio != null);

  /*当item进入列表的时候，最少需要进入item的当前方向尺寸的比例
  例如0.5，则垂直滑动的时候，一个item进入它本身高度的1/2才能能算有效的屏幕内的一个item*/
  final double minEnterRatio;

  //同上 item要列表的时候，划出去多少比例内才算有效的屏幕内的一个item
  final double maxOverRatio;
}

typedef bool IsInViewCustomerCondition(
    double itemStarPoint,
    double itemEndPoint,
    double listContentDimension,
    Size itemSize,
    BuildContext context);

class ListSingleItemInviewController {
  // 是否忽略当前的inViewItem的计算，例如列表嵌套在pageView中划出去，例如非WiFi情况下不需要计算等，会触发一次回调
  bool _forceIgnoreAllInViewItem = false;

  bool get forceIgnoreAllInViewItem => (_forceIgnoreAllInViewItem ?? false);

  triggerForceIgnoreAllInViewItemOptionChanged(
      {@required bool forceIgnoreAllInViewItem}) {
    if (forceIgnoreAllInViewItem == null ||
        forceIgnoreAllInViewItem == this.forceIgnoreAllInViewItem) {
      return;
    }
    _forceIgnoreAllInViewItem = forceIgnoreAllInViewItem;
    _inViewStateCache
        ?._onForceIgnoreAllInViewItemOptionChanged(forceIgnoreAllInViewItem);
  }

  InViewState _inViewStateCache;
  List<_WidgetContextData> _cachedContents;

  dispose() {
    _inViewStateCache = null;
    _cachedContents = null;
  }
}

////  utility

// A?.B?.list ?? []).isEmpty? 
bool _checkListIsEmpty(List list) => (list == null || list.isEmpty);
int _getListLength(List list) => (_checkListIsEmpty(list)) ? 0 : list.length;
// A?.B?.C?.int??0
int _nonnullIntFromInt(int value, {int defaultValue = 0}) {
  assert(defaultValue != null);
  return value ?? defaultValue;
}
