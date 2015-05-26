統一發票對獎
=================

又到了對獎的時間，不趕快寫個對獎程式就來不及惹 Zzz

## Usage
僅止於目前，還要做發票表匯入功能

```ruby
lottery = Lottery.new
puts lottery.check_lottery "04296940"
```

## Todos
* 包成 gem
* 發票表匯入
* multithread 優化那僅止於一兩次的爬蟲
