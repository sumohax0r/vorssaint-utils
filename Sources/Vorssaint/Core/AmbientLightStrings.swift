// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AmbientLightStrings {
    let title: String
    let description: String
    let behavior: String
    let scaleHint: String
    let threshold: String
    let defaultMode: String
    let returnTriggerFormat: String
    let aboveTriggerFormat: String
    let dark: String
    let light: String
    let currentLight: String
    let waiting: String
    let unavailable: String
    let appearanceUnavailable: String
    let paused: String
}

extension FeatureStrings {
    static func ambientLight(_ language: AppLanguage) -> AmbientLightStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .fr: return .fr
        case .de: return .de
        case .it: return .it
        case .sk: return .sk
        case .tr: return .tr
        case .ru: return .ru
        case .uk: return .uk
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension AmbientLightStrings {
    static let enUS = AmbientLightStrings(
        title: "Ambient light mode",
        description: "Switch macOS appearance automatically as the ambient light changes.",
        behavior: "Switches after four stable seconds. A 25% buffer below the trigger prevents frequent changes. While enabled, this feature controls the system appearance.",
        scaleHint: "10 steps: dim rooms → bright indoor light → outdoor daylight.",
        threshold: "Trigger level",
        defaultMode: "Default appearance (below trigger)",
        returnTriggerFormat: "Return to %@ at or below %@.",
        aboveTriggerFormat: "At or above trigger: %@",
        dark: "Dark",
        light: "Light",
        currentLight: "Current ambient light",
        waiting: "Waiting for sensor…",
        unavailable: "Ambient light sensor unavailable. This feature needs a readable built-in light sensor.",
        appearanceUnavailable: "macOS appearance could not be changed.",
        paused: "Paused while the Mac sleeps or this session is inactive."
    )

    static let ptBR = AmbientLightStrings(
        title: "Modo por luz ambiente",
        description: "Muda a aparência do macOS automaticamente conforme a luz ambiente.",
        behavior: "Muda após quatro segundos estáveis. Uma margem de 25% abaixo do limite evita mudanças frequentes. Quando ativado, controla a aparência do sistema.",
        scaleHint: "10 níveis: ambientes escuros → interiores claros → luz do dia ao ar livre.",
        threshold: "Limite de luz",
        defaultMode: "Aparência padrão (abaixo do limite)",
        returnTriggerFormat: "Volta para %@ em %@ ou menos.",
        aboveTriggerFormat: "No limite ou acima: %@",
        dark: "Escuro",
        light: "Claro",
        currentLight: "Luz ambiente atual",
        waiting: "Aguardando sensor…",
        unavailable: "Sensor de luz ambiente indisponível. Este recurso precisa de um sensor integrado acessível.",
        appearanceUnavailable: "Não foi possível mudar a aparência do macOS.",
        paused: "Pausado durante o repouso do Mac ou com esta sessão inativa."
    )

    static let es = AmbientLightStrings(
        title: "Modo por luz ambiental",
        description: "Cambia la apariencia de macOS automáticamente según la luz ambiental.",
        behavior: "Cambia tras cuatro segundos estables. Un margen del 25% bajo el umbral evita cambios frecuentes. Al activarse, controla la apariencia del sistema.",
        scaleHint: "10 niveles: habitaciones tenues → interiores luminosos → luz diurna exterior.",
        threshold: "Umbral de luz",
        defaultMode: "Apariencia predeterminada (bajo el umbral)",
        returnTriggerFormat: "Vuelve a %@ con %@ o menos.",
        aboveTriggerFormat: "En el umbral o por encima: %@",
        dark: "Oscuro",
        light: "Claro",
        currentLight: "Luz ambiental actual",
        waiting: "Esperando al sensor…",
        unavailable: "Sensor de luz ambiental no disponible. Se necesita un sensor integrado accesible.",
        appearanceUnavailable: "No se pudo cambiar la apariencia de macOS.",
        paused: "En pausa mientras el Mac está en reposo o esta sesión está inactiva."
    )

    static let fr = AmbientLightStrings(
        title: "Mode selon la lumière ambiante",
        description: "Change automatiquement l’apparence de macOS selon la lumière ambiante.",
        behavior: "Bascule après quatre secondes stables. Une marge de 25 % sous le seuil évite les changements fréquents. Cette fonction contrôle l’apparence du système.",
        scaleHint: "10 niveaux : pièces tamisées → intérieur lumineux → lumière du jour extérieure.",
        threshold: "Seuil de lumière",
        defaultMode: "Apparence par défaut (sous le seuil)",
        returnTriggerFormat: "Revient à %@ à %@ ou moins.",
        aboveTriggerFormat: "Au seuil ou au-dessus : %@",
        dark: "Sombre",
        light: "Clair",
        currentLight: "Lumière ambiante actuelle",
        waiting: "En attente du capteur…",
        unavailable: "Capteur de lumière ambiante indisponible. Un capteur intégré accessible est nécessaire.",
        appearanceUnavailable: "Impossible de modifier l’apparence de macOS.",
        paused: "En pause lorsque le Mac est en veille ou que cette session est inactive."
    )

    static let de = AmbientLightStrings(
        title: "Modus nach Umgebungslicht",
        description: "Ändert das Erscheinungsbild von macOS automatisch mit dem Umgebungslicht.",
        behavior: "Wechselt nach vier stabilen Sekunden. Ein Puffer von 25 % unter der Schwelle verhindert häufige Wechsel. Diese Funktion steuert die Systemdarstellung.",
        scaleHint: "10 Stufen: gedämpfte Räume → helle Innenräume → Tageslicht im Freien.",
        threshold: "Lichtschwelle",
        defaultMode: "Standarddarstellung (unter der Schwelle)",
        returnTriggerFormat: "Zurück zu %@ bei %@ oder weniger.",
        aboveTriggerFormat: "Ab der Schwelle: %@",
        dark: "Dunkel",
        light: "Hell",
        currentLight: "Aktuelles Umgebungslicht",
        waiting: "Warten auf Sensor…",
        unavailable: "Umgebungslichtsensor nicht verfügbar. Ein auslesbarer integrierter Sensor wird benötigt.",
        appearanceUnavailable: "Das Erscheinungsbild von macOS konnte nicht geändert werden.",
        paused: "Pausiert im Ruhezustand oder bei inaktiver Sitzung."
    )

    static let it = AmbientLightStrings(
        title: "Modalità luce ambientale",
        description: "Cambia automaticamente l’aspetto di macOS in base alla luce ambientale.",
        behavior: "Cambia dopo quattro secondi stabili. Un margine del 25% sotto la soglia evita cambi frequenti. Questa funzione controlla l’aspetto del sistema.",
        scaleHint: "10 livelli: stanze poco illuminate → interni luminosi → luce diurna esterna.",
        threshold: "Soglia di luce",
        defaultMode: "Aspetto predefinito (sotto la soglia)",
        returnTriggerFormat: "Torna a %@ a %@ o meno.",
        aboveTriggerFormat: "Alla soglia o oltre: %@",
        dark: "Scuro",
        light: "Chiaro",
        currentLight: "Luce ambientale attuale",
        waiting: "In attesa del sensore…",
        unavailable: "Sensore di luce ambientale non disponibile. Serve un sensore integrato leggibile.",
        appearanceUnavailable: "Impossibile cambiare l’aspetto di macOS.",
        paused: "In pausa quando il Mac è in stop o questa sessione è inattiva."
    )

    static let sk = AmbientLightStrings(
        title: "Režim podľa okolitého svetla",
        description: "Automaticky mení vzhľad macOS podľa okolitého svetla.",
        behavior: "Prepne po štyroch stabilných sekundách. Rezerva 25 % pod prahom zabraňuje častým zmenám. Táto funkcia riadi vzhľad systému.",
        scaleHint: "10 úrovní: tlmené miestnosti → svetlý interiér → denné svetlo vonku.",
        threshold: "Prah svetla",
        defaultMode: "Predvolený vzhľad (pod prahom)",
        returnTriggerFormat: "Návrat na %@ pri %@ alebo menej.",
        aboveTriggerFormat: "Na prahu alebo nad ním: %@",
        dark: "Tmavý",
        light: "Svetlý",
        currentLight: "Aktuálne okolité svetlo",
        waiting: "Čaká sa na senzor…",
        unavailable: "Senzor okolitého svetla nie je dostupný. Vyžaduje sa čitateľný vstavaný senzor.",
        appearanceUnavailable: "Vzhľad macOS sa nepodarilo zmeniť.",
        paused: "Pozastavené počas spánku Macu alebo neaktívnej relácie."
    )

    static let tr = AmbientLightStrings(
        title: "Ortam ışığı modu",
        description: "Ortam ışığına göre macOS görünümünü otomatik olarak değiştirir.",
        behavior: "Dört saniye kararlı kaldıktan sonra geçiş yapar. Eşiğin altında %25 pay, sık değişiklikleri önler. Bu özellik sistem görünümünü kontrol eder.",
        scaleHint: "10 seviye: loş odalar → aydınlık iç mekân → dışarıda gün ışığı.",
        threshold: "Işık eşiği",
        defaultMode: "Varsayılan görünüm (eşiğin altında)",
        returnTriggerFormat: "%@ moduna %@ veya altında döner.",
        aboveTriggerFormat: "Eşikte veya üzerinde: %@",
        dark: "Koyu",
        light: "Açık",
        currentLight: "Geçerli ortam ışığı",
        waiting: "Sensör bekleniyor…",
        unavailable: "Ortam ışığı sensörü kullanılamıyor. Okunabilir yerleşik bir ışık sensörü gerekir.",
        appearanceUnavailable: "macOS görünümü değiştirilemedi.",
        paused: "Mac uyurken veya bu oturum etkin değilken duraklatılır."
    )

    static let ru = AmbientLightStrings(
        title: "Режим по освещённости",
        description: "Автоматически меняет оформление macOS в зависимости от освещённости.",
        behavior: "Переключает после четырёх стабильных секунд. Запас 25% ниже порога предотвращает частые изменения. Функция управляет оформлением системы.",
        scaleHint: "10 уровней: тусклый свет → яркое освещение в помещении → дневной свет на улице.",
        threshold: "Порог освещённости",
        defaultMode: "Оформление по умолчанию (ниже порога)",
        returnTriggerFormat: "Возврат к %@ при %@ или ниже.",
        aboveTriggerFormat: "На пороге или выше: %@",
        dark: "Тёмное",
        light: "Светлое",
        currentLight: "Текущая освещённость",
        waiting: "Ожидание датчика…",
        unavailable: "Датчик освещённости недоступен. Нужен встроенный датчик с доступными показаниями.",
        appearanceUnavailable: "Не удалось изменить оформление macOS.",
        paused: "Приостановлено во время сна Mac или неактивного сеанса."
    )

    static let uk = AmbientLightStrings(
        title: "Режим за освітленістю",
        description: "Автоматично змінює оформлення macOS залежно від освітленості.",
        behavior: "Перемикає після чотирьох стабільних секунд. Запас 25% нижче порога запобігає частим змінам. Функція керує оформленням системи.",
        scaleHint: "10 рівнів: тьмяне світло → яскраве освітлення в приміщенні → денне світло надворі.",
        threshold: "Поріг освітленості",
        defaultMode: "Типове оформлення (нижче порога)",
        returnTriggerFormat: "Повернення до %@ за %@ або нижче.",
        aboveTriggerFormat: "На порозі або вище: %@",
        dark: "Темне",
        light: "Світле",
        currentLight: "Поточна освітленість",
        waiting: "Очікування датчика…",
        unavailable: "Датчик освітленості недоступний. Потрібен вбудований датчик із доступними показниками.",
        appearanceUnavailable: "Не вдалося змінити оформлення macOS.",
        paused: "Призупинено під час сну Mac або неактивного сеансу."
    )

    static let ja = AmbientLightStrings(
        title: "環境光モード",
        description: "周囲の明るさに合わせてmacOSの外観を自動で切り替えます。",
        behavior: "明るさが4秒間安定すると切り替えます。しきい値より25%低い復帰基準で頻繁な切り替えを防ぎます。有効な間はシステムの外観を制御します。",
        scaleHint: "10段階：薄暗い室内 → 明るい室内 → 屋外の昼光。",
        threshold: "切り替えのしきい値",
        defaultMode: "標準の外観（しきい値未満）",
        returnTriggerFormat: "%@に戻る明るさ：%@以下。",
        aboveTriggerFormat: "しきい値以上：%@",
        dark: "ダーク",
        light: "ライト",
        currentLight: "現在の周囲の明るさ",
        waiting: "センサーを待機中…",
        unavailable: "環境光センサーを利用できません。読み取り可能な内蔵光センサーが必要です。",
        appearanceUnavailable: "macOSの外観を変更できませんでした。",
        paused: "Macのスリープ中またはこのセッションが非アクティブの間は一時停止します。"
    )

    static let ko = AmbientLightStrings(
        title: "주변광 모드",
        description: "주변 밝기에 따라 macOS 화면 모드를 자동으로 변경합니다.",
        behavior: "4초간 안정되면 전환합니다. 기준보다 25% 낮은 복귀 지점으로 잦은 전환을 방지합니다. 활성화된 동안 시스템 화면 모드를 제어합니다.",
        scaleHint: "10단계: 어두운 실내 → 밝은 실내 → 야외의 햇빛.",
        threshold: "전환 기준",
        defaultMode: "기본 화면 모드 (기준 미만)",
        returnTriggerFormat: "%@로 돌아가는 밝기: %@ 이하.",
        aboveTriggerFormat: "기준 이상: %@",
        dark: "다크",
        light: "라이트",
        currentLight: "현재 주변 밝기",
        waiting: "센서 대기 중…",
        unavailable: "주변광 센서를 사용할 수 없습니다. 읽을 수 있는 내장 광 센서가 필요합니다.",
        appearanceUnavailable: "macOS 화면 모드를 변경할 수 없습니다.",
        paused: "Mac이 잠자기 상태이거나 이 세션이 비활성 상태이면 일시 정지합니다."
    )

    static let zhHans = AmbientLightStrings(
        title: "环境光模式",
        description: "根据环境光自动切换 macOS 外观。",
        behavior: "光线稳定四秒后切换。恢复阈值比触发值低 25%，避免频繁切换。启用期间，此功能控制系统外观。",
        scaleHint: "10 档：昏暗室内 → 明亮室内 → 户外日光。",
        threshold: "触发阈值",
        defaultMode: "默认外观（低于阈值）",
        returnTriggerFormat: "恢复为 %@：%@ 或以下。",
        aboveTriggerFormat: "达到或高于阈值：%@",
        dark: "深色",
        light: "浅色",
        currentLight: "当前环境光",
        waiting: "等待传感器…",
        unavailable: "环境光传感器不可用。此功能需要可读取的内置光线传感器。",
        appearanceUnavailable: "无法更改 macOS 外观。",
        paused: "Mac 睡眠或此会话未激活时暂停。"
    )

    static let zhTW = AmbientLightStrings(
        title: "環境光模式",
        description: "根據環境光自動切換 macOS 外觀。",
        behavior: "光線穩定四秒後切換。恢復閾值比觸發值低 25%，避免頻繁切換。啟用期間，此功能控制系統外觀。",
        scaleHint: "10 段：昏暗室內 → 明亮室內 → 戶外日光。",
        threshold: "觸發閾值",
        defaultMode: "預設外觀（低於閾值）",
        returnTriggerFormat: "恢復為 %@：%@ 或以下。",
        aboveTriggerFormat: "達到或高於閾值：%@",
        dark: "深色",
        light: "淺色",
        currentLight: "目前環境光",
        waiting: "等待感測器…",
        unavailable: "環境光感測器無法使用。此功能需要可讀取的內建光線感測器。",
        appearanceUnavailable: "無法變更 macOS 外觀。",
        paused: "Mac 睡眠或此工作階段未啟用時暫停。"
    )

    static let zhHK = AmbientLightStrings(
        title: "環境光模式",
        description: "根據環境光自動切換 macOS 外觀。",
        behavior: "光線穩定四秒後切換。回復閾值比觸發值低 25%，避免頻繁切換。啟用期間，此功能控制系統外觀。",
        scaleHint: "10 段：昏暗室內 → 明亮室內 → 戶外日光。",
        threshold: "觸發閾值",
        defaultMode: "預設外觀（低於閾值）",
        returnTriggerFormat: "回復為 %@：%@ 或以下。",
        aboveTriggerFormat: "達到或高於閾值：%@",
        dark: "深色",
        light: "淺色",
        currentLight: "目前環境光",
        waiting: "等待感應器…",
        unavailable: "環境光感應器無法使用。此功能需要可讀取的內置光線感應器。",
        appearanceUnavailable: "無法更改 macOS 外觀。",
        paused: "Mac 睡眠或此階段未啟用時暫停。"
    )

}
