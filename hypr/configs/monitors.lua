-- 모니터 배치 — 손으로 관리한다 (nwg-displays 사용 안 함).
--
-- 이 파일이 "설정의 source of truth"다. scripts/clamshell.sh 의 restore_internal()이
-- `hyprctl reload`로 이 파일을 다시 적용해 내장 패널을 되살리므로, eDP-1은 여기서
-- 항상 "켜진 상태"여야 한다. 클램쉘(덮개 닫힘 + AC + 외부)일 때 끄는 것은
-- clamshell.sh가 런타임에 hl.monitor{ disabled = true } eval로 처리한다.
--
-- position은 논리 좌표다. DP-1 3840x2160 @scale 1.5 → 2560x1440 이므로
-- eDP-1(3840x2400 @scale 2 → 1920x1200)을 그 아래 가운데 정렬하면 320x1440.
-- DP-1 scale을 바꾸면 이 좌표도 같이 고칠 것.

hl.monitor({
    output = "eDP-1",
    mode = "3840x2400@60.0",
    position = "320x1440",
    scale = 2,
    --bitdepth = 10,
    cm = "auto"
})
-- USB-C 포트를 바꿔 꽂으면 커넥터 이름이 DP-1 ↔ DP-4로 바뀐다(예전 nwg 백업에도
-- 둘 다 남아있다). 포트명 대신 desc:로 고정해야 어느 포트에 꽂든 규칙이 붙는다.
-- USB-C(DisplayPort) 입력은 HDMI 입력과 EDID가 다르다: RGB 4:4:4 10bpc 지원.
-- (HDMI 입력은 TMDS 600MHz 상한 때문에 10bit가 4:2:0에서만 가능했다)
hl.monitor({
    output = "desc:Samsung Electric Company Smart M70D H1AK500000",
    mode = "3840x2160@60.0",
    position = "0x0",
    scale = 1.5,
    bitdepth = 10,
    cm = "dp3"
})
