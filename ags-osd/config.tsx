#!/usr/bin/env -S ags run
import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import { createState, createComputed } from "ags"
import { timeout } from "ags/time"
import { execAsync } from "ags/process"
import Gtk from "gi://Gtk"
import css from "./style.css"

// 1. 상태 관리
const [show, setShow] = createState(false)
const [mode, setMode] = createState("volume")
const [percent, setPercent] = createState(0)
const [muted, setMuted] = createState(false)

let hideTimer: any;

// 2. 시스템 값을 읽어오고 OSD를 띄우는 함수
async function triggerOsd(m: string) {
    setMode(m)
    let p = 0
    let isMuted = false

    try {
        if (m === "volume") {
            const out = await execAsync("wpctl get-volume @DEFAULT_AUDIO_SINK@")
            // "Volume: 0.50 [MUTED]" 형태에서 MUTED 감지
            isMuted = out.includes("[MUTED]")
            const match = out.match(/Volume:\s+([\d\.]+)/)
            if (match) p = Math.round(parseFloat(match[1]) * 100)
        } else {
            const out = await execAsync("brightnessctl -m")
            const match = out.match(/,(\d+)%,/)
            if (match) p = parseInt(match[1])
        }
    } catch (e) {
        console.error(e)
    }

    setPercent(p)
    setMuted(isMuted)
    setShow(true)

    if (hideTimer) hideTimer.cancel()
    hideTimer = timeout(2000, () => {
        setShow(false)
    })
}

// 3. UI 위젯 컴포넌트 렌더링
function OsdWindow() {
    const iconName = createComputed(() => {
        if (mode() === "brightness") return "display-brightness-symbolic"
        if (muted() || percent() === 0) return "audio-volume-muted-symbolic"
        return "audio-volume-high-symbolic"
    })

    const percentText = createComputed(() => {
        if (mode() === "volume" && muted()) return "Muted"
        return `${percent()}%`
    })

    const progressValue = createComputed(() => {
        if (mode() === "volume" && muted()) return 0
        return percent() / 100
    })

    return (
        <window
            visible={show}
            anchor={Astal.WindowAnchor.BOTTOM}
	    namespace="ags-osd"
        >
            <box class="osd-container">
                <image iconName={iconName} class="osd-icon" valign={Gtk.Align.CENTER} />
                <box class="progress-wrapper" valign={Gtk.Align.CENTER} hexpand={true}>
                    <levelbar value={progressValue} class="osd-progress" hexpand={true} />
                </box>
                <label label={percentText} class="osd-label" valign={Gtk.Align.CENTER} />
            </box>
        </window>
    )
}

// 4. AGS 앱 실행
app.start({
    instanceName: "osd",
    css: css,
    requestHandler(argv, response) {
    	const cmd = argv[0]
    	if (cmd.startsWith("volume:")) {
        	const raw = cmd.substring(7) // "Volume: 0.55 [MUTED]" 등
        	const isMuted = raw.includes("[MUTED]")
        	const match = raw.match(/([\d\.]+)/)
        	const p = match ? Math.round(parseFloat(match[1]) * 100) : 0

        	setMode("volume")
        	setPercent(p)
        	setMuted(isMuted)
        	setShow(true)

        	if (hideTimer) hideTimer.cancel()
        	hideTimer = timeout(2000, () => setShow(false))
        	response("ok")
    	} else if (cmd.startsWith("brightness:")) {
        	const p = parseInt(cmd.substring(11)) || 0

        	setMode("brightness")
        	setPercent(p)
        	setMuted(false)
        	setShow(true)

        	if (hideTimer) hideTimer.cancel()
        	hideTimer = timeout(2000, () => setShow(false))
        	response("ok")
    	} else if (cmd.startsWith("power:")) {
        	triggerPowerOsd(cmd.split(":")[1])
        	response("ok")
    	} else {
        	response("unknown")
    	}
    },
    main() {
        OsdWindow()
    },
})
