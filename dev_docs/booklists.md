# 在线书单（账号页 → 我的书单）

## 结构

- `providers/booklists_provider.dart`：`BooklistsController`（`NotifierProvider.autoDispose`）。管理「我的书单 / 发现书单」两个标签、搜索、排序（`order`：popular / date_created / date_updated）、分页，以及缓存先显示再后台刷新。状态用 `BooklistsPhase`（loading / loggedOut / error / ready）表示，页面只负责渲染。另有 `RecommendedBooklistsController`（发现页顶部的推荐书单）。
- `providers/booklist_detail_provider.dart`：`BooklistDetailController`（按书单 id 的 family）和 `BooklistDetailArgs`。第一页来自详情页 HTML，第二页起走 JSON 接口；后台重新校验时只替换第一页，已加载的后续页保留。移书优先用详情页卡片自带的条目 id（`booklistsindex`），缺失时再查 `current-user`；单本书备注走 `save-description`。
- `services/booklist_solver.dart`：Dio 被浏览器检查页拦截时，改用 WebView 解题取 HTML 的共用逻辑（验证页判断、登录会话注入、清除 Cookie 同步、写入缓存）。列表页和详情页共用，不再各抄一份。
- `widgets/booklist_card.dart`：`BooklistCard`（列表卡片）、`BooklistGridCard`（网格卡片）、`BooklistCover`、`BooklistMetaPill(s)`、`BooklistSkeletonList`（加载骨架）。卡片带颜色条、私密锁标、收藏爱心与「…」菜单（编辑/改颜色/公开私有/收藏/分享/删除）。
- `widgets/booklist_row.dart`：紧凑行样式，仍由用户主页的书单区块使用。
- `utils/booklist_colors.dart`：6 种书单颜色的渐变（Marine / Velvet / Night Blue / Green / Yellow / Red）。渐变色值未从站点实测，系按名取的近似值，待站内样式核对。

## 界面

- 列表页：大标题折叠 AppBar、胶囊搜索框、带图标的分段切换、排序按钮（最受欢迎/最新创建/最近更新）与列表/网格切换、卡片式或网格书单、发现页顶部的推荐书单、加载骨架、下拉刷新。
- 详情页：大封面 + 标题/作者/数量标签的头部，描述超过三行可点击展开；自己的书单里每本书行尾有「…」菜单（备注/移出），备注显示在书名下方。

## 行为约定

- 过期请求由 `_generation` 丢弃：切换标签、搜索、重试、刷新都会递增，慢响应不会覆盖当前视图。
- 后台刷新失败不报错，保留缓存内容。
- 写接口均已接入：新建/编辑/删除书单、加书/移书（移书取条目 id）、改颜色、公开私有切换、收藏/取消收藏、单本书备注。加书选择器走 `current-user` 全量接口，带成员旗标、本地搜索与内联新建。
