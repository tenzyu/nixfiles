# neko5 / osu!lazer 最大性能・実装先行プロファイル（2026-11-12）

## 管理情報

- 基準: `tenzyu/nixfiles` main `956dac3d3ba51f52af2d89109c5635f6d614ba94`、2026-11-12。OS/Hyprland実機: Linux 7.3.3、Hyprland 0.57.2、i915 Comet Lake-U、1366×768@60.003Hz。
- 正本: `neko5-fullscreen-20261112-204449.tar.gz` SHA256 `f3ee74d2d2496bb5775e16a4252361ee925cefaad900b1fb6c9a7e8b926e3d9c`。2026-11-07の20テキスト・後続Audio採取は別の時間点であり混同しない。
- 目的: **osu!frameworkが許すInput・Audio・Update・Drawの能力を取りこぼさず、実機neko5で競技処理の遅延と尾部ジッターを最小化**。単に全設定を最小/最大へ固定しない。ゲーム動作・判定精度・安定性を壊す「高速化」は不採用。
- 不変条件: Native Wayland / SDL3、OpenGL、ゲーム内1280×720、既知の`fullscreen=2/fullscreenClient=0`、Direct Scanout、内蔵OTD（外部daemon無効）、既存のAudioローカル出力、SplitCastによるゲームへの同期依存なし。Vulkan/Zink、Gamescope強制、GLフック、特権OBS、未合意の恒久カーネル引数を採用しない。
- 証拠の優先: **上流該当rev実装**＞仕様書・バグ報告＞neko5実機スナップショット（その条件でのみ最優先）＞第三者の独立実験＞仮説。実測を要求する前にソースから消せる仮説を消す。

## 1. Fullscreen回帰：今回のアーカイブから修正判断

| 時刻・状態 | n | IPC結果 | 解釈 |
| --- | ---: | --- | --- |
| osu! `2/0` | 10 | `directScanoutTo != 0`, `directScanoutBlockedBy = null` | 現行0.57.2でもDS経路へ到達。成功条件を維持 |
| osu! `2/2` | 3 | `directScanoutTo = 0`, `directScanoutBlockedBy = [TRANSFORM]` | 2/2下ではDS条件不成立。Hyprland IPCでTRANSFORMは **surface transformations** |
| osu! `0/0` | 1 | `CANDIDATE` | ウィンドウが fullscreen から外れた状態 |
| 未検出 | 1 | `CANDIDATE` | 無関係なサンプル |

14秒間の一連の遷移は `2/2→2/0→0/0→2/0→2/2→2/0` を含む。ログの`TRANSFORM`は出力の画面回転を断定する値ではなく、surface transformations のカテゴリー。IPCの`directScanoutTo`はHyprlandの`m_lastScanout`に由来するため、15点を「全フレームscanout率」とみなさない。映像停止・swap stallの時刻は採取されていない。

上流 `Hyprland v0.57.2` の `src/config/lua/bindings/LuaBindingsDispatchers.cpp::dsp_fullscreenState` で、デフォルト`action=toggle`は`internal`と`client`を**それぞれ**現状態と比較して、同じなら0に戻す。したがって現在`2/2`、目標`2/0`のtoggleは`0/0`になり得る。`2/0`から押しても`0/0`。`window.fullscreen`と`fullscreen_client`がLua APIに存在することは`LuaWindow.cpp`で確定。osu!framework Issue #6828はSDLのEnter/Leave Fullscreenイベントに対してFrameworkSetting.WindowModeが追随しない問題を記述（Open Issue）。

**採用する修正**: osu!の`Win+F`だけは`2/0`に**明示的set**、すでに`2/0`なら`0/0`に明示的set。重複する起動時`fullscreen_state="2 0"`と`immediate=true`ルールを除去。他のアプリは元のtoggleを維持。`render.direct_scanout=1`とグローバルallow_tearingは変更しない。前回提案の動作と一致するが、今回は実機の状態遷移で補強した。

**採否**: `Win+F`から`2/0`へ移行し、前面でDS target非0・blocked null、入力・画面更新正常。`2/2`へ戻る、freeze継続の場合は採用保留。互換性のためNixOS旧generationへロールバック可能。

## 2. Input：HIDイベントが判定に合流するまで

`O3C switch firmware scan/debounce → USB Full-Speed interrupt IN 1ms (device descriptor) → xHCI completion IRQ → usbhid → input core → evdev queue/SYN_REPORT → libinput → Hyprland Wayland keyboard → SDL3 → KeyboardHandler.handleKeyDown/up → PendingInputs.Enqueue → InputManager.GetPendingInputs → CurrentState.Apply → OsuInputManager / hit judgement`。マウス/キーボードのSDLイベントタイムスタンプは確認した`KeyboardHandler`では`KeyboardKeyInput`へ転写されず、Updateで処理する設計。よって頻度の増加だけで物理押下時刻へ遡及できない。

`CTL-472 digitizer → USB hub 1-4.2 → 2ms interval HID endpoint → in-process OTD → OpenTabletDriverHandler.enqueueInput → InputManager.GetPendingInputs`。端点の2msはhost予約周期で、レポート発生率・座標分解能・ジッターを同一視しない。外部OTD daemonを再導入しない。`usbhid.mousepoll=1`はHIDペンの2ms記述子を書き換えない。

**次のコード作業**: osu!frameworkを派生計装ビルドし、SDL timestampを別枠で保管してから、`KeyboardHandler.enqueueInput`、`InputManager.GetPendingInputs`、判定直前の順序をリングバッファに記録。1イベントずつconsoleへ出力しない。上流ゲーム判定時刻は変更しない。キーボードのポーリング用専用スレッドやIRQ固定を根拠なく足さない。

## 3. Audio：BASS `-256`の採用候補と、他方式との差

neko5ではユーザーが`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-256`で**明確なプレイ改善**、DTのカスタムとFUNで異常なしと報告。これは現在の重要な採用候補として保持する。ただし11月12日の更新でosu!バイナリ/BASSバージョンが変わった可能性と、全曲の互換性は別問題。

上流経路: `SampleChannelBass.Play → AudioComponent.EnqueueAction(new Task(action)) → ConcurrentQueue<Task> → Audio ThreadのAction実行 → BassAudioMixer.ChannelPlay → BassMix.MixerAddChannel / MixerChanPause解除 → BASS PCM生成 → PipeWire ALSA plug → PipeWire driver → ALSA snd_hda_intel → ALC257 DAC`。各ヒットで新しいOSスレッドが作られるわけでも、ロード済みの音声ファイルが毎回ファイルから全デコードされるわけでもない。`Task`の割当、Audio Threadキュー待ち、ミキサー出力時刻、PipeWire graph、ALSA buffer、DACは独立する。

上流には既に`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD`があり、BASS周期と`DeviceBufferLength=1`の要求を設定できる。`-256`要求は44.1kHzで約5.805ms、48kHzで約5.333ms。最低2周期分への丸めは要求値どおりの物理出力バッファを保証しない。

`rszyma/osu-latency-tweaker/src/basscallwrap.c`は`BASS_Init`を改造し `BASS_CONFIG_DEV_PERIOD`、`BASS_CONFIG_DEV_BUFFER` を差し込む。作者のreadmeは**ALSA直接選択時**に有用と位置付け、PipeWire Serverでは`PIPEWIRE_ALSA`/`PIPEWIRE_QUANTUM`を代替可能と説明する。neko5は既にBASS側の環境変数を使えるため、独自パッチlibbass.so、排他的ALSA、LD_PRELOADは今は不要。とくにSplitCastのローカル音声複製を阻害し得る。

`grish11/osutop/screens/audio.py`は`pw-top`の`QUANT/RATE×1000`を`audioLatency`とする。これはPipeWire処理周期であって、マウス→ヒットサウンドのend-to-end遅延ではない。表示名は移植せず、`pw-top`のbusy/wait/ERRとBASSの`minbuf`/`latency`を別々に公開する。`osutop`がNixOS非対応と記す理由は作者未検証/標準パス利用という主張だが、`/proc`と`/sys`が通常NixOSに無いわけではない。実行可能性は各コマンドのパスや依存による。

**採用するコード作業**: `scripts/osu-performance/osu-lazer-bass256.sh`を追加。プロセス環境変数だけをセットして`exec osu-lazer`する。通常ランチャーとNixOS/ユーザーのデフォルトは変更しない。プレイを通じ採用が固まれば後でデフォルト化を検討。BASSmixに関して2026年6月の短周期クラッシュ報告あり、2026年10月に上流ライブラリ更新。未知を「安全確定」としない。

## 4. Update/Draw：1000Hz上限と2層の機構

`GameHost.updateFrameSyncMode()`の`Limit8x`は、リフレッシュ率RでDraw=`min(8R,1000)`、Update=`min(16R,1000)`（通常のMultiThread）。R=60.003HzならDraw 480.024Hz、Update 960.048Hz **設定上の目標**。`Unlimited`ではGameHostが通常Draw/Updateの双方を1000Hzへ抑制する。これらは処理された実フレーム数ではない。最大性能という目標だけでUnlimitedが実機のtail latencyを改善するとは限らないが、8xを「1000/1000」と表現するのも誤り。

`GameThread`のper-frame scheduler→`Root.UpdateSubTree`→masking→`GenerateDrawNodeSubtree`→TripleBuffer<DrawNode>→Draw Thread→GL submit→Mesa Intel Iris→i915→SDL_GL_SwapWindow→Hyprland→KMS。`GameHost.Swap`のGL VSync時には`WaitUntilIdle`（GL Finish）による同期待ちが入り得る。`WindowMode`と`fullscreenClient`の不一致はsurface transformを増やし、合成必要性を増やす。`Direct Scanout`はHyprland合成パスを省略できるが、GPU処理・KMS/vblank・LCD応答を消さない。

**次のコード作業**: Updateの`Root.UpdateSubTree`・`GenerateDrawNodeSubtree`、DrawのGL submission・Swap区間を個別の単調時計timestampでリングバッファ追跡。ゲーム外のGPU overlayを導入しない。`Limit8x`/Unlimited/VRRを判断する前に上流コードのcap意味を維持し、1ms以下の不合理な外部スピンループを追加しない。

## 5. SplitCastは設計を停止しない

ゲームの`Swap`や音声出力callbackをhookしない。neko5で最小権限KMS broker→DMA-BUF FD（SCM_RIGHTS、実際のmodifier/stride/fenceをチェック）→iHD VAAPIのRGB→NV12変換/encode→有界キュー（遅い配信フレームのみ破棄）→Tailscale→neko7（デコード/AV同期/OBS・overlay・TTS・Twitch）。音声はローカルBASS→PipeWire→ALC257を変更せず、PipeWire application streamを独立に複製。録画/配信失敗はゲーム処理・音声・Direct Scanoutに伝播させない。raw scanoutへ戻すためにゲーム内レンダラーを改造しない。

1366×768×4B×60 = **251,781,120B/s（251.78MB/s）**。GPU readback経由で全画面をCPU転送すると、この量のバス/メモリ転送と同期が加わる。DMA-BUFも転送・同期・color conversionは必ずしも0にならない。SplitCastでDSが失われる方式は棄却する。現在のRust stub/Python実装は移行目録であり、性能最適な理想仕様の根拠ではない。

## 6. 次の作業順と完了条件

| 優先 | 作業 | 実装が保証する内容 | 完了の意味 |
| --- | --- | --- | --- |
| P0 | 2/2→2/0 Fullscreenの明示的setと二重rule除去 | 既知のDS成功状態を狙う。toggleの0/0副作用をなくす | `2/0`・DS正常・ゲーム表示/input正常、失敗時旧generationへ戻せる |
| P0 | -256 BASS専用launcher追加 | `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-256`を起動時だけ設定 | 通常launcher不変、DT/FUNを含む既知成功条件維持 |
| P1 | osu!framework Input/Audio/Update/Drawのリングバッファ計装案を具体実装 | コスト/待機点をコードレベルで分離 | ゲーム側情報に欠落なし、ログI/Oがcritical pathへ入らない |
| P1 | NixOSネイティブ監視TUIへosutop項目を正しく移植 | Graph quantum、BASS period、DS、各レイヤーの別単位表示 | q/rを音響E2E遅延と誤表記しない |
| P1 | SplitCast KMS DMA-BUF・VAAPI workerのprivilege設計とRust移植 | game↔capture同期依存なし、圧縮経路、有界キュー | ゲーム単独のDSを失わない設計・制約が仕様/ADR/テスト化 |
| P2 | Source-code-level Option `Limit8x`/Unlimitedの根拠比較 | Update/Drawフレーム生成負荷の理論予算を確定 | 目標数値を上流上限から求め、設定を無根拠に改変しない |

## 7. 外部一次資料と技術根拠

1. Hyprland v0.57.2 `src/config/lua/bindings/LuaBindingsDispatchers.cpp`、`src/config/lua/objects/LuaWindow.cpp`、`src/ipc/s1/Commands.cpp`（`TRANSFORM = surface transformations`）。
2. [osu!framework #6828](https://github.com/ppy/osu-framework/issues/6828) external fullscreen changes desync FrameworkSetting.WindowMode。
3. [osutop](https://github.com/grish11/osutop) `screens/audio.py`、`screens/display.py`、README。
4. [osu-latency-tweaker](https://github.com/rszyma/osu-latency-tweaker) `src/basscallwrap.c`、`readme.md`。
5. [osu-lazer-flake](https://github.com/repinek/osu-lazer-flake) README。
6. osu!framework `AudioManager.cs`, `SampleChannelBass.cs`, `AudioComponent.cs`, `BassAudioMixer.cs`, `InputManager.cs`, `GameHost.cs`。
7. 旧 `docs/graphics-streaming/ADR-2026-11-07-performance-first.md` と `SPLITCAST-AGENT-PORTING-2026-11-07.md` は移行・非回帰条件であり、現在のSplitCast実装が完成している証拠ではない。
