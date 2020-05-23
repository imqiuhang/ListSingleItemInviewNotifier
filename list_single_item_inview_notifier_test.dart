import 'list_single_item_inview_notifier.dart';
import 'package:flutter/material.dart';

class ListItemInviewNotifierTestPage extends StatefulWidget {
  @override
  _ListItemInviewNotifierTestPageState createState() =>
      _ListItemInviewNotifierTestPageState();
}

class _ListItemInviewNotifierTestPageState
    extends State<ListItemInviewNotifierTestPage> {
  int itemCount = 0;

  // inView组件的区域计算以及滚动监听依赖ScrollController，所以是必传参数
  ScrollController scrollController = ScrollController();

  // ListSingleItemInviewController 可以在自己想任何需要的时候区更新inView
  ListSingleItemInviewController inviewController =
      ListSingleItemInviewController();

  @override
  void initState() {
    super.initState();

    // 模拟500毫秒后获取到数据
    Future.delayed(Duration(milliseconds: 500), () {
      reload();
    });
  }

  reload() {
    setState(() {
      itemCount += 30;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("test"),
          backgroundColor: Colors.green,
        ),
        body: Container(
          child: ListSingleItemInviewNotifier(
            //是否需要按照index来排序，false代表按照加入组件的顺序来
            findDependItemIndex: false,
            // inView组件计算依赖方向，必传
            scrollDirection: Axis.vertical,
            scrollController: scrollController,
            inviewController: inviewController,
            // 将需要计算的ListView(或者只要Widget树中含有该ListView即可)作为该组件的child
            child: ListView.separated(
              itemBuilder: (BuildContext context, int index) {
                // 使视频组件使用AnimatedBuild方案
//                return VideoPageAnimatedBuildExample(
////                    id: '$index',
////                    index: index,
////                  ),

                // 使视频组件使用StatusFull方案
                return VideoPageStatusFullExample(
                  id: '$index',
                  index: index,
                );
              },
              itemCount: itemCount,
              controller: scrollController,
              separatorBuilder: (BuildContext context, int index) {
                return Container(
                  height: 10,
                  color: Colors.white,
                );
              },
            ),
          ),
        ));
  }
}

// ************************************************************************************
// @example 1 : 使用StatusFull方案，该方案比较灵活，
//              适合需要记录状态做一些操作的组件、
//              例如视频播放，可能需要做一些暂停销毁或者打点
//************************************************************************************

class VideoPageStatusFullExample extends StatefulWidget {
  
  final String id;

  //用于item inView计算的排序，如果没有排序需要可以不用 @see findDependItemIndex
  final int index;

  const VideoPageStatusFullExample({
    Key key,
    @required this.id,
    @required this.index,
  }) : super(key: key);

  @override
  _VideoPageStatusFullExampleState createState() =>
      _VideoPageStatusFullExampleState();
}

class _VideoPageStatusFullExampleState
    extends State<VideoPageStatusFullExample> {
  InViewState _inViewState;

  @override
  void initState() {
    super.initState();

    _inViewState = ListSingleItemInviewNotifier.of(context);
    //init 的时候加入inViewItem改变的监听
    _inViewState.addListener(_onInViewStatusChanged);

    /* ⚠️ 【重要】在第一帧被渲染的时候加入context去计算
     *     将需要在计算的区域对应的item加入到计算池中
           一是基于最小化更新的原则，二是方便区域的计算，一般feed流中的区域计算都是某坑位里的一小块
    */

    WidgetsBinding.instance.addPostFrameCallback((callback) {
      _inViewState?.addContext(context: context, index: 0);
    });
  }

  @override
  void dispose() {
    // // 销毁的时候结束监听
    _inViewState.removeListener(_onInViewStatusChanged);
    super.dispose();
  }

  _onInViewStatusChanged() {
    // 当前inViewItem变化的时候回触发回调，更新自己的status ，处理自己的事务
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {

    // 判断自己是不是当前的inViewItem
    final bool isInView =
        _inViewState?.isCurrentInViewItemWithContext(context: context);

    return Container(
      width: double.infinity,
      alignment: Alignment.bottomCenter,
      color: isInView ? Colors.red : Colors.yellow,
      height: 200,
      child: Container(
        margin: EdgeInsets.only(top: 150),
        height: 50, // 刚好是1/4高度，也就是默认的区域计算方式
        color: Colors.green,
        child: Text(
          "id:" +
              widget.id +
              "  " +
              (isInView ? 'currentInViewItem' : 'notInView'),
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
