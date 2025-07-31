https://smarden.org/runit/faq



**详细解答**

**runit 是什么，它为什么如此不同？**
*   **问：** runit 是什么？为什么它与 sysvinit 和其他初始化方案如此不同？
*   **答：** 请参阅介绍以及关于 runit 优点的网页。

**我需要 runit 的帮助，该怎么办？**
*   **问：** 我有问题，runit 似乎有问题，或者我做错了什么，我该怎么办？
*   **答：** 首先查阅文档，特别是这份常见问题解答列表，如果对特定的 runit 程序有疑问，请查看其手册页 (man page)。如果这仍然不能解答您的问题，请尝试搜索监督邮件列表 (supervision mailing list) 的存档。最后，如果还是不行，请随时将您的问题发布到监督邮件列表。

**runit 的许可证是什么，它是自由软件吗？**
*   **问：** 我想以源代码和二进制形式分发 runit。我允许这样做吗？
*   **答：** runit 是自由软件，它采用类似三条款 BSD 的许可证授权。请查看 runit 压缩包中 `package/COPYING` 文件。

**如何在 runit 服务监管下运行服务？**
*   **问：** 我希望一个服务在 runit 的服务监管下运行，以便在系统启动时自动启动，并在系统运行期间受到监管。这是如何工作的？
*   **答：** runit 不使用常见的 `/etc/init.d/` init 脚本接口，而是为每个服务使用一个目录。要将服务集成到 runit 初始化方案中，请为该服务创建一个服务目录，并告知 runit。

**如何创建新的服务目录？**
*   **问：** 如何创建用于 runit 的服务目录？
*   **答：** 服务目录通常放在 `/etc/sv/` 目录下。在 `/etc/sv/` 中为您的服务创建一个新目录，在其中放入一个可执行的 `./run` 脚本。请注意，为了与 runit 一起使用，服务守护进程**不能**将自己放入后台 (daemonize/background)，而**必须**在前台运行。下面是一个简单的 getty 服务示例：
    ```bash
    $ cat /etc/sv/getty-2/run
    #!/bin/sh
    exec getty 38400 tty2 linux
    $
    ```
    **注意**最后一行中的 `exec`，它告诉解释脚本的 shell 用服务守护进程 `getty` 替换自身；这对于正确控制服务是必要的。

**如何创建一个附带日志服务的新服务目录？**
*   **问：** 如何创建一个带有附加日志服务、用于 runit 的服务目录？
*   **答：** 首先为该服务创建服务目录。然后在服务目录中创建一个 `./log` 子目录，同样在其中放入一个可执行的 `./run` 脚本。`./run` 脚本必须运行一个服务日志守护进程，通常使用 `svlogd` 程序。详情请参阅 `runsv` 手册页。以下是一个 `./log/run` 脚本的示例：
    ```bash
    $ cat /etc/sv/socklog-klog/log/run
    #!/bin/sh
    exec chpst -ulog svlogd -tt ./main
    $
    ```

**如何告知 runit 有一个新服务？**
*   **问：** 我为某个服务创建了服务目录，希望它在 runit 服务监管下运行。如何告知 runit 这个新服务目录，使其默认接管并运行该服务？
*   **答：** 在 `/service/` 目录中创建一个指向该服务目录的符号链接。runit 将在接下来的五秒钟内检测到该服务，并在系统启动时自动启动它。例如：
    ```bash
    # ln -s /etc/sv/getty-2 /service/
    ```

**如何启动、停止或重启服务？**
*   **问：** 我想暂时停止一个服务，稍后可能重启它，或者我想让它立即重启。如何控制运行在 runit 服务监管下的服务？
*   **答：** 使用 `sv` 程序。例如，要重启 `socklog-unix` 服务，执行：
    ```bash
    # sv restart socklog-unix
    ```

**如何向服务守护进程发送信号？**
*   **问：** 我想向服务守护进程发送 HUP 信号，让它重新读取配置，或者发送 INT 信号。如何向服务守护进程发送信号？
*   **答：** 使用 `sv` 程序。例如，向 `dhcp` 服务发送 HUP 信号，执行：
    ```bash
    # sv hup dhcp
    ```

**如何查询服务的状态？**
*   **问：** 我想知道某个服务的状态，它是正常运行且可用，还是按要求停止了等等。如何获取这些信息？
*   **答：** 使用 `sv` 程序。例如，要查询或检查 `socklog-unix` 服务的状态，执行：
    ```bash
    # sv status socklog-unix
    ```
    或
    ```bash
    # sv check socklog-unix
    ```

**如何移除服务？**
*   **问：** 我想移除一个当前在 runit 服务监管下运行的服务。如何告知 runit？
*   **答：** 移除 `/service/` 目录中指向该服务目录的符号链接。runit 将在接下来的五秒钟内识别到该服务已被移除，然后停止该服务、其可选的日志服务，最后停止其监管进程。例如：
    ```bash
    # rm /service/getty-2
    ```

**如何让一个服务依赖另一个服务？**
*   **问：** 我有一个服务，它需要另一个服务在启动前可用。如何告知 runit 这种依赖关系？
*   **答：** 确保在依赖服务的 `./run` 脚本中，它所依赖的服务在其守护进程启动之前是可用的。可以使用 `sv` 程序来实现这一点。例如，`cron` 服务希望在启动 `cron` 守护进程之前，`socklog-unix` 系统日志服务是可用的，这样就不会丢失日志：
    ```bash
    $ cat /etc/sv/cron/run
    #!/bin/sh
    sv start socklog-unix || exit 1
    exec cron -f
    $
    ```
    另请参阅文档。

**关于运行级别 (runlevels)？**
*   **问：** 其他初始化方案支持运行级别，runit 呢？
*   **答：** runit 支持运行级别，甚至比传统的初始化方案更灵活。请参阅文档。

**关于 LSB init 脚本兼容性？**
*   **问：** 我知道可以使用 `sv` 程序来控制服务，但有些应用程序依赖 LSB 定义的 `/etc/init.d/` 脚本接口。我需要修改应用程序才能与 runit 一起工作吗？
*   **答：** 您**不需要**修改应用程序。`sv` 程序支持 LSB 定义的 `/etc/init.d/` 脚本接口。要使此脚本接口对某个服务生效，请在 `/etc/init.d/` 中创建一个以服务守护进程命名的符号链接，指向 `sv` 程序。例如，对于 `cron` 服务：
    ```bash
    # ln -s /bin/sv /etc/init.d/cron
    # /etc/init.d/cron restart
    ok: run: cron: (pid 5869) 0s
    #
    ```

**是否可能允许 root 以外的用户控制服务？**
*   **问：** 使用 `sv` 程序控制服务或查询其状态信息只能以 root 身份进行。是否可能允许非 root 用户也控制服务？
*   **答：** **可以**，您只需调整服务目录中 `./supervise/` 子目录的文件系统权限即可。例如：要允许用户 `burdon` 控制 `dhcp` 服务，切换到 `dhcp` 服务目录，然后执行：
    ```bash
    # chmod 755 ./supervise
    # chown burdon ./supervise/ok ./supervise/control ./supervise/status
    ```
    当然，对组也可以进行类似操作。

**runit 支持用户特定的服务吗？**
*   **问：** 通过简单地创建符号链接来添加系统级服务非常方便。这对于用户特定的服务也适用吗？
*   **答：** **可以**。例如：要为用户 `floyd` 提供通过 `~/service/` 管理服务的能力，创建一个名为 `runsvdir-floyd` 的服务，其 `run` 脚本如下（并配一个常规的 `log/run` 脚本），然后告知 runit 该服务：
    ```bash
    #!/bin/sh
    exec 2>&1
    exec chpst -ufloyd runsvdir /home/floyd/service
    ```
    现在 `floyd` 可以自行创建服务，并通过在 `~/service/` 中创建符号链接来管理它们，这些服务将以其用户 ID 运行。

**runit 能在只读文件系统上工作吗？**
*   **问：** 在我的系统上，`/etc/` 默认是只读挂载的。runit 需要使用 `/etc/` 中的许多文件进行写入操作，比如 `/etc/runit/stopit` 和服务目录中的 `./supervise/` 子目录。如何让 runit 在我的系统上工作？
*   **答：** 使用符号链接。runit 能很好地处理符号链接，即使是悬空的符号链接 (dangling symlinks)。例如，将一个 RAM 磁盘挂载到某个挂载点，比如 `/var/run/`，然后为 runit 需要写入访问的文件和目录创建指向 `/var/run/` 的符号链接：
    ```bash
    # ln -s /var/run/runit.stopit /etc/runit/stopit
    # ln -s /var/run/sv.getty-2 /etc/sv/getty-2/supervise
    ```

---