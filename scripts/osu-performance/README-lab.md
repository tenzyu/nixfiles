# neko5 osu! latency lab（Input / Audio / Update / Draw）

目的：公式osu!lazerを変更せず、1回の計測で4軸を読み取り、別条件で再計測した結果をHTMLで比較する。**設定変更や最適化効果を自動判定するプログラムではない。** 4軸の検証可能性を上げる診断キット。

## 現在の基準条件（2026-11-13）

- CTL-472：1000Hz対応ファームウェア導入済み。ただし**ユーザーの現在の設定は400Hz**。1000Hzではペンクリックの信頼性に問題があるため、400Hzを基準にする。HzとDraw FPSを一致させる必要はない。実際の報告間隔はこれから測る。
- osu!：公式バイナリ・公式同梱ライブラリは無改変。OpenTabletDriverはin-process、独立daemon無効。内部表示1280×720、eDP-1は1366×768@60.003Hz、VRRなし。
- Draw：Hyprland fullscreen 2/0 + DSOが既知の成功経路。非同期提示は`osu-display`を使った**別の実験**。本ツールは`osu-display on/off`を勝手に実行しない。
- Audio：BASS -128は現在のlauncher標準、-256を安定比較候補とする。-64はクラックル報告のため通常比較に含めない。

## 使用方法

適用とシステムビルド（手動・変更を確認してから）：

```bash
cd ~/.nixfiles
# パッチを適用した後
python3 scripts/osu-performance/test-osu-lab.py
nix flake check --no-build
nh os build
# 問題なければ、旧世代を確認したうえで nh os switch
```

公式osu!を`osu-first tournament`などで起動して、`Win+F`で2/0のDSOを確立する。端末・SSH側で最初に対象デバイスを表示する：

```bash
osu-lab devices
```

次に**端末から計測を起動し、ゲームを前面に保つ**。計測を起動する端末はフォーカスを奪わないようSSHか既存のTTYなどを利用する（ゲームに戻るまでの最初の数秒は後から除外可能）。

```bash
osu-lab capture --label 400hz-8x-bass128-sync --seconds 90 \
  --tablet-hz 400 --game-settings 8x-sync --bass=-128
```

`~/osu-lab-results/YYYYMMDD-HHMMSS-400hz-8x-bass128-sync/report.html`が作られる。ローカルHTMLをFirefox等で開ける。ディレクトリ権限は0700。生ログにはアプリ・端末情報が含まれるため公開前に確認する。

`osu-lab capture`はゲームを起動/停止しない。オーディオ設定、fps limiter、ファームウェア、tearing、kernel、NixOS設定を変えない。`--bass`や`--game-settings`は**比較用ラベルで、設定が本当に変わったという主張ではない**。BASSはゲームプロセスから取得できた要求値を別途表示する。

### 比較する順番

1. **基準**：400Hz / BASS -128 / 8x / 同期提示。90秒、同じ譜面、同じ操作、同じ常駐アプリ。可能なら3試行。
2. **Audio**：osu!を終了・再起動し、`OSU_FIRST_BASS_PERIOD=-256 osu-first tournament`で起動。その他は同じにして90秒。BASS環境変数値とALSA/PipeWire状態が異なることを確認する。報告周期が変わっただけで物理発音遅延が短いとは判定しない。
3. **Draw limiter**：BASS -128、CTL-472 400Hz、同期提示を戻し、ゲーム内でUnlimitedに変更して90秒。8xとUnlimitedを比較する。内部fpsは本ツールでは採取できないので、公式統計（`Ctrl+F11`）と条件の目視確認を併用する。
4. **Draw tearing**：別スレッドの`osu-display try 12`に成功した後、`osu-display on`で明示的に有効化し、同期提示と同じ設定で90秒を比較する。計測後`osu-display off`。`activelyTearing`が観測されても物理async flipの成功とは断定しない。フリーズ時には別TTYまたは旧NixOS世代で復旧。
5. **Input**：400Hzが標準。クリックの不安定さが出た1000Hzを無条件で再採用しない。必要なら別の日にユーザーがFW設定を変え、同じ操作を再計測する。ヒストグラムだけではクリック成功率を判定できないため、別途実プレイ/クリックの信頼性を確認する。

2条件の計測を終えたら、各セッションディレクトリを渡して比較する。

```bash
osu-lab compare ~/osu-lab-results/*-400hz-8x-bass128-sync \
                ~/osu-lab-results/*-400hz-8x-bass256-sync \
                --out ~/osu-lab-results/audio-comparison
```

比較に`*`を使う場合、対象のセッションが1件ずつであることを確認すること。複数試行がある場合はディレクトリを明示的に指定する。

## 取得できるデータの由来

| 軸 | データ | 観測の限界 |
|---|---|---|
| Input | `hidraw`からのCTL-472レポート到着間隔ヒストグラム（p50/p95/p99/p99.9）、evdevの変更イベント間隔、`SYN_DROPPED`、イベントpress/release数、evdev取得までのOS側待ち | `hidraw`は**ユーザー空間で読み出した時刻**。センサー内部レートは測れない。evdevは状態が変わった時だけイベントが来る。停止時のギャップは欠落の証拠ではない。`SYN_DROPPED`はこの観測者のevdevキュー損失であり、osu!側の損失を証明しない。Input→Updateをイベントごとに追跡はできない。 |
| Audio | `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD`（**要求**）、ALSA playback `hw_params`、WirePlumber/PipeWire node props、`pw-top -b` ERR増分 | BASSの実効内部periodとDAC/耳への発音開始は不可視。ERRはXRun＋他のエラー。ALSA hw_paramsとPipeWireノードの対応は型・パスで追加確認が必要。 |
| Update | `/proc/$pid/cgroup`と`cpu.weight/uclamp`、`timerslack_ns`、`task/*/schedstat` runqueue累積待機時間、CPU温度/周波数、slow-frameログ | `schedstat`のwait/sliceは**Update間隔ではない**。全Updateのp99/p99.9や入力→Update待ち時間にはin-process instrumentationが必要。プロセス名が判別できなければ`--pid`を使う。 |
| Draw | 前面・2/0・DSOの一致率、`activelyTearing`、熱、slow-frameログ | DSOとtearingのHyprland状態は1秒毎の点サンプル。Per-frame KMS flip、GPU完了、パネルの発光、input-to-photonは測れない。|

### 公式osu!の詳細診断

`Ctrl+F11`は画面内のInput/Audio/Update/Drawフレーム統計。`Ctrl+F2`はパフォーマンスログの詳細機能。**frameworkソースの`BackgroundStackTraceCollector.NewFrame`は閾値超過の遅いフレームを選択的に記録するため、`performance-update.log`のデータで全フレームp99を計算してはいけない**。`osu-lab`は計測開始以後に追記されたperformance-*.logのみ最大2MBずつ保存し、遅いフレーム数・最大値だけを集計する。

`--logs /path/to/osu/logs`で保存先を指定できる。自動探索候補は`~/.local/share/osu[/logs]`、`~/.local/share/osu-lazer[/logs]`、`~/.config/osu[/logs]`。ログが見つからなければ未測定と報告する。

### 権限・負荷・失敗時

- `osu-lab devices`で見つけたCTL-472の`/dev/hidrawN`にアクセスできない場合は`unavailable`を報告。rootやudevの一括緩和を自動実行しない。カスタムFWで名前/VIDが変わった場合は`--hidraw /dev/hidrawN`で手動指定する。
- SayoDevice O3Cなど`/dev/input/eventN`への読み取りは権限が必要。`--event /dev/input/eventN`でも指定可能。**このツールはEVIOCGRABを使用せず、書き込み・キー注入・firmware更新をしない**。生の座標やキーコードは保存しない。
- 標準では1HzでHyprland/CPU/スレッドを照会し、`pw-top`を非対話batchで動作させる。これはプロファイリングによる負荷を加えるため、試行間で条件をそろえること。レイテンシに厳密なA/Bでは同じ計測方法を両群へ適用する。
- マルチセッションでnixfilesを更新した場合、比較前にバージョンや起動世代の差を確認すること。
- 早期終了は`Ctrl+C`でレポートを保存。ドライバ/音声/Hyprlandが応答しない場合は各指標を欠測として表示し、成功扱いにしない。
- 保存先はデフォルト`~/osu-lab-results/`、生ログは非公開扱い。`report.html`と`analysis.json`の内容を確認してから共有すること。

## 計測できないものの別ルート

- **Input→Updateのイベント単位待機時間**：特定入力に識別子とmonotonic timestampを付け、osu!の入力消費位置で記録する必要がある。これは公式バイナリ無改変条件では通常利用できず、一般的な`/proc`メトリクスでは代替不能。
- **ゲーム内部の全Update/Drawフレーム時間**：framework公開の統計overlayや診断ログの範囲を超える場合は、ユーザーが同意した別ビルド/公式計測機能、または非侵襲のGPU/CPUトレースと十分な相関づけが必要。ゲームを改変して大会で使うことはしない。
- **i915非同期page-flipの成功率/タイムスタンプ**：DRM tracepoint/perf/trace-cmdなどで対象CRTCとの相関を取る。通常はtracefs権限、時刻同期、trace overheadの評価が必要であり、本ツールの既定動作にrootを要求する計測は含めない。
- **実音・発光の時刻**：物理マイク/ループバックとイベント同期、または高速撮影/フォトダイオードが必要。ユーザーの現有設備だけで実測済みとはしない。

一次資料：
- [Linux evdev input](https://docs.kernel.org/input/input.html)、[event codes (SYN_DROPPED)](https://docs.kernel.org/input/event-codes.html)、[hidraw](https://docs.kernel.org/hid/hidraw.html)
- [osu! Client Menu tips](https://osu.ppy.sh/wiki/en/Client/Menu_tips)、[osu!framework PerformanceMonitor.cs](https://github.com/ppy/osu-framework/blob/0d5edae7264553239183f38ea32fdb5ef2a98dd9/osu.Framework/Statistics/PerformanceMonitor.cs)、[BackgroundStackTraceCollector.cs](https://github.com/ppy/osu-framework/blob/0d5edae7264553239183f38ea32fdb5ef2a98dd9/osu.Framework/Statistics/BackgroundStackTraceCollector.cs)
- [PipeWire pw-top](https://docs.pipewire.org/page_man_pw_top_1.html)、[ALSA WirePlumber](https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html)
- [Hyprland v0.57.2 Monitor.cpp](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/output/Monitor.cpp)、[DRM UAPI](https://docs.kernel.org/gpu/drm-uapi.html)
