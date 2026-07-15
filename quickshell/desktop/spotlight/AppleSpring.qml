import QtQuick

SpringAnimation {
    spring: ThemeService.spring
    damping: ThemeService.criticalDamping
    epsilon: 0.002
}
