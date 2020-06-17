# ListSingleItemInviewNotifier

#### 有时间会打包到pub上去

##### 以下简称 `InviewNotifier`
##### 这是什么？
> InviewNotifier是一个通用的ListView(或其他滚动容器)的item可见优先级变化(inView状态)处理组件


##### 举个栗子


> 在一个feed流中穿插视频模块，在该视频模块 1/4高度进入到feed流时开始播放
>  在3/4高度区域离开feed流时停止播放并寻找播放下一个符合条件的视频
> 如果已经有正在播放的则不受影响。


##### 已有的特性

*  仅需在滚动容器外层套一个InviewNotifier并指定滚动方向即可，无需其他代码，无页面层级限制
*  页面首次初始化、页面刷新等自动重新计算
*  自定义添加需要用于监测的widget，可以是滚动容器item或item里的任意子widget，例如添加一个视频文章item里的播放器widget作为监测模块，不受视图层级影响
*  通过.of方法在任意层级里都可以获取当前的InView状态
*  横向纵向均支持
*  提供默认的Inview条件计算(即例子中的计算方式)，也可自定义注入Inview条件的计算判断逻辑
*  默认计算无优先级，可指定排序方式
*  可手动暂停，适用于一个页面有多个tab切换的情况
*  每次列表滚动结束后重新计算
*  计算结果和上一次相同不会触发回调

##### 如何使用？
1. 将滚动容器作为InviewNotifier的child(或在子树中包含滚动容器的widget都可)，并指定滚动方向
2. 在滚动容器的item里需要作为计算的widget state里加上需要的功能，例如在包含播放器的widget的state init的时候添加如下代码

```dart
class _VideoState extends State<VideoWidget> {
  InViewState _inViewState;  
  @override
  void initState() {
    super.initState();
    // 1. 通过of方法获取当前页面的InViewState管理实例
    _inViewState = KLAListSingleItemInviewNotifier.of(context);
    // 2. 注册inView item变化的监听
    _inViewState?.addListener(_updatePlayStatus);
    // 3，在首帧渲染回调中将自己加入到计算池中(为什么是在这个时机加入后面会解释)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inViewState?.addContext(context: context, index: null);
    });
  }
  
  @override
  void dispose() {
    // 在组件销毁的时候移除监听 并且将自己移除计算池
    _inViewState?.removeListener(_updatePlayStatus);
    _inViewState?.removeContext(context: context);
    super.dispose();
  }
    _updatePlayStatus() {
    // 获取自己是不是当前inview的item
    bool isCurrentInView =
        _inViewState?.isCurrentInViewItemWithContext(context: context);
    if (isCurrentInView) _play(); else _pause();
  }
}

```
* 具体各种使用姿势都在kla_list_item_inview_notifier_test.dart 里有详细的介绍

##### 组件工作原理
![流程图](https://github.com/imqiuhang/ListSingleItemInviewNotifier/blob/master/feed%E6%B5%81%E6%BB%9A%E5%8A%A8%E6%92%AD%E6%94%BE%E6%8E%A7%E5%88%B6%E7%BB%84%E4%BB%B6.jpg)
