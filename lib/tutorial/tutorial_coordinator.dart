import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

/// Stable anchors for the real widgets used by the DETECT-CO tutorial.
class TutorialTargets {
  TutorialTargets._();

  static final homeBarangay = GlobalKey(debugLabel: 'tutorial-home-barangay');
  static final homeRisk = GlobalKey(debugLabel: 'tutorial-home-risk');
  static final homeWeather = GlobalKey(debugLabel: 'tutorial-home-weather');
  static final homeWater = GlobalKey(debugLabel: 'tutorial-home-water');
  static final homeRainfall = GlobalKey(debugLabel: 'tutorial-home-rainfall');
  static final bottomNavigation = GlobalKey(
    debugLabel: 'tutorial-bottom-navigation',
  );
  static final bottomMenu = GlobalKey(debugLabel: 'tutorial-bottom-menu');
  static final toolsSections = GlobalKey(debugLabel: 'tutorial-tools-sections');
  static final toolsEmergencyAlarm = GlobalKey(
    debugLabel: 'tutorial-tools-emergency-alarm',
  );
  static final toolsSosFlashlight = GlobalKey(
    debugLabel: 'tutorial-tools-sos-flashlight',
  );
  static final toolsEmergencyLocation = GlobalKey(
    debugLabel: 'tutorial-tools-emergency-location',
  );
  static final toolsLocalAi = GlobalKey(debugLabel: 'tutorial-tools-local-ai');
  static final mapSearch = GlobalKey(debugLabel: 'tutorial-map-search');
  static final mapFilters = GlobalKey(debugLabel: 'tutorial-map-filters');
  static final mapLegend = GlobalKey(debugLabel: 'tutorial-map-legend');
  static final mapMlRisk = GlobalKey(debugLabel: 'tutorial-map-ml-risk');
  static final mapNearestResources = GlobalKey(
    debugLabel: 'tutorial-map-nearest-resources',
  );
  static final mapLocateMe = GlobalKey(debugLabel: 'tutorial-map-locate-me');
  static final notificationTabs = GlobalKey(
    debugLabel: 'tutorial-notification-tabs',
  );
  static final menuHowToUse = GlobalKey(debugLabel: 'tutorial-menu-how-to-use');
}

enum TutorialLanguage { english, filipino }

extension TutorialLanguageLabel on TutorialLanguage {
  String get shortLabel => this == TutorialLanguage.english ? 'EN' : 'FIL';
}

@immutable
class TutorialCardPlacement {
  const TutorialCardPlacement({
    required this.alignment,
    required this.maxHeight,
    required this.top,
    required this.bottom,
  });

  final Alignment alignment;
  final double maxHeight;
  final double top;
  final double bottom;
}

/// Positions a card in the larger clear area around its spotlight target.
/// When neither side can fit the controls, it anchors the card to the safer
/// screen edge and lets the description scroll.
TutorialCardPlacement tutorialCardPlacement({
  required Rect? targetRect,
  required Size screenSize,
  required EdgeInsets safeInsets,
}) {
  const edgePadding = 12.0;
  const targetGap = 12.0;
  final top = safeInsets.top + edgePadding;
  final bottom = screenSize.height - safeInsets.bottom - edgePadding;
  final safeHeight = (bottom - top).clamp(0.0, screenSize.height);
  final visibleTarget =
      targetRect != null &&
          targetRect.overlaps(Rect.fromLTRB(0, top, screenSize.width, bottom))
      ? targetRect
      : null;
  final roomAbove = visibleTarget == null
      ? 0.0
      : (visibleTarget.top - top - targetGap).clamp(0.0, safeHeight);
  final roomBelow = visibleTarget == null
      ? 0.0
      : (bottom - visibleTarget.bottom - targetGap).clamp(0.0, safeHeight);
  // Use the larger side when it can hold the fixed controls. Otherwise place
  // the card at the screen edge farthest from the target and scroll its body.
  final above = roomAbove >= roomBelow;
  // Leave enough space for the title, language toggle and fixed controls;
  // small residual space is worse than a scrollable safe-edge card.
  final hasRoom = (above ? roomAbove : roomBelow) >= 270;
  final placeTop = visibleTarget == null
      ? true
      : hasRoom
      ? !above
      : visibleTarget.center.dy > (top + bottom) / 2;
  final cardTop = hasRoom && !above ? visibleTarget!.bottom + targetGap : top;
  final cardBottom = hasRoom && above
      ? screenSize.height - visibleTarget!.top + targetGap
      : screenSize.height - bottom;
  return TutorialCardPlacement(
    alignment: placeTop ? Alignment.topCenter : Alignment.bottomCenter,
    maxHeight: (hasRoom ? (above ? roomAbove : roomBelow) : safeHeight)
        .clamp(0.0, 420.0)
        .toDouble(),
    top: cardTop,
    bottom: cardBottom,
  );
}

/// A screen-bounded card layer independent of tutorial_coach_mark's
/// target-relative content positioning. It recalculates after metrics change.
class TutorialCardOverlay extends StatelessWidget {
  const TutorialCardOverlay({
    super.key,
    required this.targetRect,
    required this.cardBuilder,
  });

  final Rect? targetRect;
  final Widget Function(TutorialCardPlacement placement) cardBuilder;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final placement = tutorialCardPlacement(
      targetRect: targetRect,
      screenSize: media.size,
      safeInsets: media.viewPadding,
    );
    return Positioned(
      left: 12,
      right: 12,
      top: placement.top,
      bottom: placement.bottom,
      child: Align(
        alignment: placement.alignment,
        child: cardBuilder(placement),
      ),
    );
  }
}

@immutable
class TutorialCopy {
  const TutorialCopy({required this.title, required this.body});

  final String title;
  final String body;
}

const List<TutorialCopy> tutorialEnglishCopy = [
  TutorialCopy(
    title: 'Welcome to DETECT-CO',
    body:
        'DETECT-CO helps you check community flood and preparedness information. This selector changes the barangay name shown here; it does not by itself confirm which sensor or forecast area supplied the data.',
  ),
  TutorialCopy(
    title: 'Flood risk status',
    body:
        'This status is based on the app’s water-rise reading. Check the sensor and reading status too; “Safe” is not a guarantee that flooding cannot occur.',
  ),
  TutorialCopy(
    title: 'Temperature and humidity',
    body:
        'These cards show temperature in °C and humidity in %. Values may come from the sensor or weather fallback; check the app’s status before relying on them.',
  ),
  TutorialCopy(
    title: 'Water rise',
    body:
        'Water rise is calculated from sensor distance using the app’s 150 cm baseline. If readings are unavailable or old, do not treat the gauge as current.',
  ),
  TutorialCopy(
    title: 'Rainfall and forecast',
    body:
        'Rainfall is shown in millimeters. Current weather data and ML rainfall forecasts are different kinds of information; a forecast is not a measured sensor reading.',
  ),
  TutorialCopy(
    title: 'Move around the app',
    body:
        'Use the bottom bar to move between Tools, Map, Home, Notifications, and Menu.',
  ),
  TutorialCopy(
    title: 'Tools and resources',
    body:
        'Tools is the first item in the bottom bar. Inside it, choose Evacuation, Emergency, Guides, or Tools for the information and actions in that section.',
  ),
  TutorialCopy(
    title: 'Emergency alarm',
    body:
        'In Tools > Tools, tap START EMERGENCY ALARM to play a continuous alarm sound on this phone. Tap STOP EMERGENCY ALARM to stop it. It does not send an alert to responders.',
  ),
  TutorialCopy(
    title: 'SOS signal',
    body:
        'In Tools > Tools, tap START SOS FLASHLIGHT to send a repeating SOS flash from your phone’s torch. The button changes to STOP SOS while active. This does not contact emergency services.',
  ),
  TutorialCopy(
    title: 'Flashlight controls',
    body:
        'There is no separate steady flashlight switch. The SOS control flashes the camera torch; tap STOP SOS to stop it. It works only when the device has an available torch.',
  ),
  TutorialCopy(
    title: 'Emergency Locate Me',
    body:
        'Wait through the 10-second confirmation, then allow location access to share your GPS position with the emergency response system. The session sends location updates, shows a persistent notification, and expires after 30 minutes. GPS, permission, internet, and Firebase access are required; you can stop it early.',
  ),
  TutorialCopy(
    title: 'Local AI assistant',
    body:
        'Open Local AI from Tools > Tools. Tap Load AI if needed, wait for the model to download and load, then type a question and tap Send. Ask about DETECT-CO, floods, typhoons, or preparedness. The first download needs internet and storage; after loading, answers are generated on this Android device. Treat advice as general information and follow official emergency instructions.',
  ),
  TutorialCopy(
    title: 'Search places on the map',
    body:
        'Search by evacuation-center or hospital name, then tap a result to move the map and open its details. Use X to clear a search. Drag to pan and pinch to zoom the map.',
  ),
  TutorialCopy(
    title: 'Map filters',
    body:
        'Turn Evacuation Centers, Hospitals, or Flood Areas on or off. A selected chip means that layer is shown. The map can still be panned and zoomed with touch gestures.',
  ),
  TutorialCopy(
    title: 'Map legend and symbols',
    body:
        'The legend labels Normal (0–4 cm rise), Flooding (5–40 cm), and Critical (>40 cm). Tap Map symbols to expand or hide the extra marker key.',
  ),
  TutorialCopy(
    title: 'ML flood-risk details',
    body:
        'Tap this summary to see the model risk level and rainfall forecasts for 1, 3, 6, 12, and 24 hours. If the water sensor is unavailable, the summary says UNAVAILABLE; forecasts are not sensor measurements.',
  ),
  TutorialCopy(
    title: 'Nearest emergency locations',
    body:
        'Nearest evacuation center ranks centers using availability, flood-zone status, and distance; Full and Unavailable centers are excluded. Nearest hospital uses distance. Both may ask for location permission and show details with route options. Check current conditions and official advice.',
  ),
  TutorialCopy(
    title: 'Your location and map markers',
    body:
        'Show my location asks for GPS permission and moves the map to your position. Tap a marker for details: evacuation centers offer Go to Location and Directions from Me; hospitals offer Go to Hospital. The map remains usable if location is unavailable.',
  ),
  TutorialCopy(
    title: 'Announcements and alerts',
    body:
        'Review saved announcements and alerts here. The unread badge shows unread items stored by the app.',
  ),
  TutorialCopy(
    title: 'Replay this tutorial',
    body: 'You can replay this tour any time from Menu → How to Use.',
  ),
  TutorialCopy(
    title: 'DETECT-CO home-screen widget',
    body:
        'The widget shows sensor status, temperature, rain chance, and flood status. Temperature uses the sensor when its reading is fresh; otherwise it uses Open-Meteo. Rain chance comes from Open-Meteo. IDLE means the sensor is unavailable or its reading is invalid or stale. To add it, touch and hold an empty area of your Android home screen, open Widgets, find DETECT-CO, then drag the widget onto the screen. Launcher labels vary by device. Tap the widget to open DETECT-CO. Updates need a network connection and Android may delay background refreshes.',
  ),
];

const List<TutorialCopy> tutorialFilipinoCopy = [
  TutorialCopy(
    title: 'Maligayang pagdating sa DETECT-CO',
    body:
        'Tumutulong ang DETECT-CO na tingnan ang impormasyon tungkol sa baha at paghahanda sa komunidad. Dito pinipili ang pangalang barangay na ipinapakita; hindi nito awtomatikong kinukumpirma kung aling sensor o lugar ang pinagmulan ng datos.',
  ),
  TutorialCopy(
    title: 'Kalagayan ng panganib sa baha',
    body:
        'Batay ang status na ito sa sukat ng pagtaas ng tubig. Tingnan din kung maayos at bago ang datos ng sensor. Hindi garantiya ang “Safe” na walang pagbaha.',
  ),
  TutorialCopy(
    title: 'Temperatura at halumigmig',
    body:
        'Ipinapakita rito ang temperatura sa °C at halumigmig sa %. Maaaring galing ang mga halaga sa sensor o sa weather service; tingnan ang status bago ito pagbatayan.',
  ),
  TutorialCopy(
    title: 'Pagtaas ng tubig',
    body:
        'Kinakalkula ang pagtaas ng tubig mula sa layo ng sensor gamit ang 150 cm na panimulang sukat ng app. Kung walang datos o luma na ito, huwag ituring na kasalukuyan ang gauge.',
  ),
  TutorialCopy(
    title: 'Ulan at pagtataya',
    body:
        'Millimeter ang yunit ng ulan. Magkaiba ang kasalukuyang datos ng panahon at ang pagtataya ng ML; hindi sukat ng sensor ang pagtataya.',
  ),
  TutorialCopy(
    title: 'Paglipat sa iba’t ibang bahagi',
    body:
        'Gamitin ang ibabang menu para lumipat sa Tools, Map, Home, Notifications, at Menu.',
  ),
  TutorialCopy(
    title: 'Mga kagamitan at mapagkukunan',
    body:
        'Ang Tools ang unang bahagi sa ibabang menu. Sa loob nito, piliin ang Evacuation, Emergency, Guides, o Tools para makita ang impormasyon at mga aksyon.',
  ),
  TutorialCopy(
    title: 'Emergency alarm',
    body:
        'Sa Tools > Tools, pindutin ang START EMERGENCY ALARM para magpatunog nang tuloy-tuloy ng alarm sa teleponong ito. Pindutin ang STOP EMERGENCY ALARM para ihinto. Hindi ito nagpapadala ng alerto sa responders.',
  ),
  TutorialCopy(
    title: 'SOS signal',
    body:
        'Sa Tools > Tools, pindutin ang START SOS FLASHLIGHT para magpaulit-ulit ng SOS na ilaw gamit ang torch ng telepono. Magiging STOP SOS ang button habang aktibo. Hindi ito direktang tumatawag sa emergency services.',
  ),
  TutorialCopy(
    title: 'Pagkontrol sa flashlight',
    body:
        'Walang hiwalay na steady flashlight switch. Kumikislap ang torch gamit ang SOS control; pindutin ang STOP SOS para ihinto. Kailangan ng device na may gumaganang torch.',
  ),
  TutorialCopy(
    title: 'Emergency Locate Me',
    body:
        'Hintaying matapos ang 10-segundong kumpirmasyon, saka payagan ang access sa lokasyon para maibahagi ang GPS position mo sa emergency response system. Nagpapadala ito ng mga update, nagpapakita ng tuloy-tuloy na notification, at kusang nagtatapos pagkalipas ng 30 minuto. Kailangan ang GPS, pahintulot, internet, at Firebase; maaari mo itong ihinto nang mas maaga.',
  ),
  TutorialCopy(
    title: 'Local AI assistant',
    body:
        'Buksan ang Local AI sa Tools > Tools. Pindutin ang Load AI kung kailangan, hintaying ma-download at ma-load ang model, saka mag-type ng tanong at pindutin ang Send. Magtanong tungkol sa DETECT-CO, baha, bagyo, o paghahanda. Kailangan ng internet at storage sa unang download; pagkatapos ma-load, sa Android device ginagawa ang sagot. Pangkalahatang impormasyon lang ito; sundin ang opisyal na tagubilin sa emergency.',
  ),
  TutorialCopy(
    title: 'Maghanap ng lugar sa mapa',
    body:
        'Maghanap gamit ang pangalan ng evacuation center o ospital, at pindutin ang resulta para puntahan ito sa mapa at buksan ang detalye. Gamitin ang X para burahin ang paghahanap. I-drag ang mapa para gumalaw at kurutin para mag-zoom.',
  ),
  TutorialCopy(
    title: 'Mga filter sa mapa',
    body:
        'I-on o i-off ang Evacuation Centers, Hospitals, o Flood Areas. Ipinapakita ang layer kapag napili ang chip. Maaari pa ring i-drag at i-zoom ang mapa.',
  ),
  TutorialCopy(
    title: 'Legend at mga simbolo sa mapa',
    body:
        'Ipinapaliwanag ng legend ang Normal (0–4 cm na pagtaas), Flooding (5–40 cm), at Critical (>40 cm). Pindutin ang Map symbols para ipakita o itago ang dagdag na gabay sa mga marker.',
  ),
  TutorialCopy(
    title: 'Detalye ng ML flood risk',
    body:
        'Pindutin ang buod para makita ang antas ng panganib at pagtataya ng ulan sa loob ng 1, 3, 6, 12, at 24 na oras. Kapag walang sensor, UNAVAILABLE ang nakalagay; hindi sukat ng sensor ang pagtataya.',
  ),
  TutorialCopy(
    title: 'Pinakamalapit na serbisyong pang-emergency',
    body:
        'Isinasaalang-alang ng nearest evacuation center ang availability, baha sa lugar, at layo. Hindi isinasama ang Full at Unavailable. Layo naman ang batayan sa nearest hospital. Maaaring hingin ng dalawa ang pahintulot sa lokasyon at magbukas ng detalye at mga opsyon sa ruta. Suriin pa rin ang aktuwal na kalagayan at opisyal na abiso.',
  ),
  TutorialCopy(
    title: 'Lokasyon mo at mga marker sa mapa',
    body:
        'Humihingi ng pahintulot sa GPS ang Show my location at inililipat ang mapa sa kinaroroonan mo. Pindutin ang marker para sa detalye: may Go to Location at Directions from Me ang evacuation center; may Go to Hospital ang ospital. Magagamit pa rin ang mapa kahit walang lokasyon.',
  ),
  TutorialCopy(
    title: 'Mga anunsyo at alerto',
    body:
        'Dito makikita ang mga naka-save na anunsyo at alerto. Ipinapakita ng badge kung may hindi pa nababasang item.',
  ),
  TutorialCopy(
    title: 'Ulitin ang gabay na ito',
    body: 'Maaari mong ulitin ang gabay anumang oras sa Menu → How to Use.',
  ),
  TutorialCopy(
    title: 'Widget ng DETECT-CO sa home screen',
    body:
        'Ipinapakita ng widget ang status ng sensor, temperatura, tsansa ng ulan, at status ng baha. Sensor ang pinagmumulan ng temperatura kapag sariwa ang sukat; kung hindi, Open-Meteo ang ginagamit. Mula sa Open-Meteo ang tsansa ng ulan. Ibig sabihin ng IDLE ay hindi available ang sensor o luma/hindi wasto ang sukat. Para idagdag: pindutin nang matagal ang bakanteng bahagi ng Android home screen, buksan ang Widgets, hanapin ang DETECT-CO, at i-drag ito sa screen. Maaaring iba ang tawag sa mga menu depende sa device. Pindutin ang widget para buksan ang DETECT-CO. Kailangan ng internet para mag-update at maaaring maantala ng Android ang pag-refresh sa background.',
  ),
];

class TutorialStepCard extends StatelessWidget {
  const TutorialStepCard({
    super.key,
    required this.language,
    required this.stepIndex,
    required this.onLanguageChanged,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    required this.isLast,
    required this.canGoBack,
    required this.maxHeight,
  });

  final ValueListenable<TutorialLanguage> language;
  final int stepIndex;
  final ValueChanged<TutorialLanguage> onLanguageChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;
  final bool canGoBack;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TutorialLanguage>(
      valueListenable: language,
      builder: (context, selectedLanguage, _) {
        final copies = selectedLanguage == TutorialLanguage.english
            ? tutorialEnglishCopy
            : tutorialFilipinoCopy;
        final copy = copies[stepIndex];
        final filipino = selectedLanguage == TutorialLanguage.filipino;
        final media = MediaQuery.of(context);
        final currentSafeHeight =
            media.size.height - media.viewPadding.vertical - 24;
        return Material(
          color: const Color(0xFF303030),
          borderRadius: BorderRadius.circular(18),
          elevation: 12,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 32)
                  .clamp(0.0, 340.0)
                  .toDouble(),
              maxHeight: maxHeight.clamp(0.0, currentSafeHeight).toDouble(),
            ),
            child: Padding(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 360 ? 12 : 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          copy.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => onLanguageChanged(
                          filipino
                              ? TutorialLanguage.english
                              : TutorialLanguage.filipino,
                        ),
                        child: Text(filipino ? 'EN' : 'FIL'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        copy.body,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${stepIndex + 1}/${tutorialEnglishCopy.length}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: onSkip,
                        child: Text(filipino ? 'Laktawan' : 'Skip'),
                      ),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    children: [
                      if (canGoBack)
                        TextButton(
                          onPressed: onBack,
                          child: Text(filipino ? 'Bumalik' : 'Back'),
                        ),
                      FilledButton(
                        onPressed: onNext,
                        child: Text(
                          isLast
                              ? (filipino ? 'Tapos na' : 'Finish')
                              : (filipino ? 'Susunod' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
