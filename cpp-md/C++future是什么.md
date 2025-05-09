# C++ Future 全面指南：掌握异步编程的核心工具

## 引言

在现代C++编程中，异步操作已成为提高程序性能的关键手段。C++11引入的`std::future`及相关工具为我们提供了强大的异步编程能力。本文将全面介绍`std::future`的使用方法，帮助你掌握这一并发编程的核心工具。

## 一、Future基础概念

`std::future`是一个模板类，代表一个异步操作的结果。它就像一张"欠条"——当你启动一个异步任务时，它会给你一个future对象，承诺将来会有一个结果。

```cpp
#include <future>
#include <iostream>

int simple_task() { return 42; }

int main() {
    std::future<int> result = std::async(std::launch::async, simple_task);
    std::cout << "The answer is: " << result.get() << std::endl;
    return 0;
}
```

## 二、Future的三种创建方式

### 1. 使用std::async

`std::async`是最简单的创建future的方式，它自动创建一个后台线程执行任务。

```cpp
auto future = std::async(std::launch::async, []{
    std::this_thread::sleep_for(std::chrono::seconds(1));
    return "Hello from future!";
});

std::cout << future.get() << std::endl;
```

### 2. 使用std::promise

`std::promise`允许你显式设置future的值，适合需要精细控制的情况。

```cpp
std::promise<std::string> promise;
auto future = promise.get_future();

std::thread([&promise]{
    promise.set_value("Promise fulfilled!");
}).detach();

std::cout << future.get() << std::endl;
```

### 3. 使用std::packaged_task

`std::packaged_task`将可调用对象与future关联，适合需要多次执行的任务。

```cpp
std::packaged_task<int(int,int)> task([](int a, int b){
    return a + b;
});

auto future = task.get_future();
std::thread(std::move(task), 2, 3).detach();

std::cout << "2 + 3 = " << future.get() << std::endl;
```

## 三、Future的核心操作

### 1. 获取结果(get)

`get()`是future最重要的方法，它会阻塞直到结果可用。

```cpp
auto future = std::async([]{
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    return 3.14159;
});

double pi = future.get();  // 阻塞直到结果就绪
```

### 2. 等待结果(wait)

如果只需要等待而不需要结果，可以使用`wait()`。

```cpp
future.wait();  // 只是等待，不获取值
```

### 3. 超时等待(wait_for/wait_until)

```cpp
auto status = future.wait_for(std::chrono::milliseconds(100));
if (status == std::future_status::ready) {
    // 结果已就绪
} else if (status == std::future_status::timeout) {
    // 超时
}
```

## 四、高级特性

### 1. 异常处理

异步任务中的异常会通过future传递。

```cpp
auto future = std::async([]{
    throw std::runtime_error("Oops!");
    return 0;
});

try {
    future.get();
} catch (const std::exception& e) {
    std::cerr << "Caught: " << e.what() << std::endl;
}
```

### 2. 共享future(shared_future)

当多个线程需要访问同一个结果时使用。

```cpp
std::promise<void> ready_promise;
std::shared_future<void> ready_future = ready_promise.get_future().share();

auto worker = [ready_future](int id) {
    ready_future.wait();  // 所有worker等待同一个事件
    std::cout << "Worker " << id << " started\n";
};

std::thread t1(worker, 1);
std::thread t2(worker, 2);

ready_promise.set_value();  // 触发所有worker
```

## 五、最佳实践与陷阱

1. **不要忘记获取结果**：未被获取的future析构时会阻塞
2. **不要多次调用get()**：会导致未定义行为
3. **注意线程安全**：future对象本身不是线程安全的
4. **合理选择启动策略**：
   - `std::launch::async`：立即异步执行
   - `std::launch::deferred`：延迟到get()时执行

## 六、实际应用案例

### 并行计算示例

```cpp
double compute_pi(size_t iterations) {
    double sum = 0.0;
    for (size_t i = 0; i < iterations; ++i) {
        double term = 1.0 / (2 * i + 1);
        sum += (i % 2 == 0) ? term : -term;
    }
    return 4.0 * sum;
}

int main() {
    auto fut1 = std::async(std::launch::async, compute_pi, 1'000'000'000);
    auto fut2 = std::async(std::launch::async, compute_pi, 1'000'000'000);
    
    double pi1 = fut1.get();
    double pi2 = fut2.get();
    
    std::cout << "Average: " << (pi1 + pi2) / 2 << std::endl;
}
```

## 结语

`std::future`是C++并发编程中不可或缺的工具，它为我们提供了一种优雅的方式来处理异步操作的结果。通过合理使用future及其相关组件，我们可以构建出高效、响应迅速的应用程序。希望本文能帮助你掌握这一强大工具，在实际项目中发挥它的最大价值。