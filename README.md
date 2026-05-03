主に増えたのは Neovim、tmux、zsh の3系統です。

Neovim
<leader> は Space です。つまり <leader>e は Space e です。

- Space e: ファイルツリーを開閉
- Space ff: ファイル検索
- Space fg: 全文検索
- Space fb: 開いているバッファ一覧
- Space fr: 最近開いたファイル
- Space fs: 現在ファイルのシンボル一覧
- Space xx: 診断一覧
- Space xw: 現在バッファだけの診断一覧
- Space gg: lazygit をターミナルで起動
- gd: 定義へ移動
- gD: 宣言へ移動
- gr: 参照一覧
- gi: 実装へ移動
- K: ホバー表示
- Space rn: シンボル rename
- Space ca: code action
- Space f: LSP フォーマット
- Space w: 保存
- Space q: 終了
- Space h/j/k/l: ウィンドウ移動
- ]w / [w: 日本語や英単語のまとまり単位で前後移動
- insert モードの Ctrl-W: 英単語だけでなく日本語の連続文字列もまとめて削除しやすくした版

tmux
prefix は Ctrl-j です。

- Ctrl-j |: 横分割
- Ctrl-j -: 縦分割
- Ctrl-j Enter: 縦分割
- Ctrl-j h/j/k/l: pane 移動
- Ctrl-j H/J/K/L: pane リサイズ
- Ctrl-j c: 現在ディレクトリで新しい window
- Ctrl-j g: lazygit 用 window を開く
- Ctrl-j A: セッション名を入力して attach / create
- Ctrl-j Ctrl-a: 直前の window に戻る

copy mode は vi です。

- Ctrl-j [ で copy mode に入る
- v: 選択開始
- y: コピーして終了
- Esc: copy mode を抜ける

zsh
alias / function を増やしています。

- lg: lazygit
- tn: tmux new -As main
- ta: tmux attach -t main
- tls: tmux ls
- tm: main セッションへ attach/create
- tm work: work セッションへ attach/create
- gdiffstaged: staged diff の要約と本体を表示
- gmsg: staged diff から Codex にコミットメッセージ案を1行生成させる
- gcai: gmsg の結果でそのまま git commit -m ...

おすすめの普段の流れはこれです。

1. tn
2. window 1 で nvim
3. 必要なら Ctrl-j g で lazygit
4. 編集は Space e と Space ff
5. rename は Space rn
6. stage 後に gmsg か gcai

必要なら次に「毎日使う最低限の運用フロー」を 10 分版でまとめます。
