# PCL2 构建工具

构建启用 MC 下载的 PCL，并发布到本仓库的 GitHub Releases。

每天检查上游默认分支中 `最新正式版.zip` 最近一次变更的提交 SHA，不依赖上游创建 GitHub Release 或 Tag。

- 从该提交的 `ModBase.vb` 读取版本号，固定检出该 SHA 后应用补丁并构建。
- 将成功构建的上游 SHA 记录在本仓库 Release 说明的 `Upstream commit: <SHA>` 中。
- SHA 相同则跳过；SHA 不同、没有发布记录或手动勾选 `force` 时构建。旧 Release 没有 SHA 记录时会重新构建一次。
- Release 标签保持 `pcl-<版本号>-patched`；同版本发布包更新时替换附件并更新 SHA 记录，客户端也通过该记录识别同版本更新。

可在 Actions 中手动运行工作流；`force` 会重新构建最近的正式版发布包提交。

检测逻辑测试：`pwsh -NoProfile -File tests/check-upstream-release.tests.ps1`。测试使用模拟接口，不访问 GitHub，也不会发布 Release。
