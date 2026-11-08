# 在线书单（账号页 → 我的书单）

## 结构

- `providers/booklists_provider.dart`：`BooklistsController`（`NotifierProvider.autoDispose`）。管理「我的书单 / 发现书单」两个标签、搜索、分页，以及缓存先显示再后台刷新。状态用 `BooklistsPhase`（loading / loggedOut / error / ready）表示，页面只负责渲染。
- `providers/booklist_detail_provider.dart`：`BooklistDetailController`（按书单 id 的 family）和 `BooklistDetailArgs`。第一页来自详情页 HTML，第二页起走 JSON 接口；后台重新校验时只替换第一页，已加载的后续页保留。
- `services/booklist_solver.dart`：Dio 被浏览器检查页拦截时，改用 WebView 解题取 HTML 的共用逻辑（验证页判断、登录会话注入、清除 Cookie 同步、写入缓存）。列表页和详情页共用，不再各抄一份。
- `widgets/booklist_card.dart`：`BooklistCard`（列表卡片）、`BooklistCover`、`BooklistMetaPill(s)`、`BooklistSkeletonList`（加载骨架）。
- `widgets/booklist_row.dart`：紧凑行样式，仍由用户主页的书单区块使用。

## 界面

- 列表页：大标题折叠 AppBar、胶囊搜索框、带图标的分段切换、卡片式书单、加载骨架、下拉刷新。
- 详情页：大封面 + 标题/作者/数量标签的头部，描述超过三行可点击展开。

## 行为约定

- 过期请求由 `_generation` 丢弃：切换标签、搜索、重试、刷新都会递增，慢响应不会覆盖当前视图。
- 后台刷新失败不报错，保留缓存内容。
- 新建书单已接入；往书单加书、删除书单的写接口尚未抓到，未实现。
