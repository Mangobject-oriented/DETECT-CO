import 'package:detectco/tutorial/tutorial_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card placement stays within safe space at phone and tablet sizes', () {
    const sizes = [Size(320, 568), Size(360, 640), Size(800, 1280)];
    for (final size in sizes) {
      for (final centerY in [40.0, size.height / 2, size.height - 40]) {
        final placement = tutorialCardPlacement(
          targetRect: Rect.fromCenter(
            center: Offset(size.width / 2, centerY),
            width: 64,
            height: 64,
          ),
          screenSize: size,
          safeInsets: const EdgeInsets.only(top: 24, bottom: 24),
        );
        expect(placement.maxHeight, greaterThanOrEqualTo(210));
        expect(placement.maxHeight, lessThanOrEqualTo(size.height - 72));
        expect(placement.top, greaterThanOrEqualTo(0));
        expect(placement.bottom, greaterThanOrEqualTo(0));
        expect(
          placement.top + placement.bottom + placement.maxHeight,
          lessThanOrEqualTo(size.height),
        );
      }
    }

    for (final missingTarget in <Rect?>[null, Rect.zero]) {
      final placement = tutorialCardPlacement(
        targetRect: missingTarget,
        screenSize: const Size(320, 480),
        safeInsets: const EdgeInsets.only(top: 24, bottom: 24),
      );
      expect(placement.top, greaterThanOrEqualTo(24));
      expect(placement.bottom, greaterThanOrEqualTo(24));
      expect(placement.maxHeight, lessThanOrEqualTo(408));
    }
  });

  test(
    'tutorial copy is available in English and Filipino for all 21 steps',
    () {
      expect(tutorialEnglishCopy, hasLength(21));
      expect(tutorialFilipinoCopy, hasLength(21));
      expect(tutorialEnglishCopy.first.title, 'Welcome to DETECT-CO');
      expect(
        tutorialFilipinoCopy.first.title,
        contains('Maligayang pagdating'),
      );
      expect(tutorialEnglishCopy[7].title, 'Emergency alarm');
      expect(tutorialEnglishCopy[8].title, 'SOS signal');
      expect(tutorialEnglishCopy[9].title, 'Flashlight controls');
      expect(tutorialEnglishCopy[10].title, 'Emergency Locate Me');
      expect(tutorialEnglishCopy[11].title, 'Local AI assistant');
      expect(tutorialEnglishCopy[12].title, 'Search places on the map');
      expect(tutorialEnglishCopy[13].title, 'Map filters');
      expect(tutorialEnglishCopy[14].title, 'Map legend and symbols');
      expect(tutorialEnglishCopy[15].title, 'ML flood-risk details');
      expect(tutorialEnglishCopy[16].title, 'Nearest emergency locations');
      expect(tutorialEnglishCopy[17].title, 'Your location and map markers');
      expect(tutorialEnglishCopy.last.title, contains('home-screen widget'));
      expect(tutorialFilipinoCopy.last.title, contains('home screen'));
    },
  );

  test('widget explanation describes real data and launcher setup', () {
    final english = tutorialEnglishCopy.last.body;
    final filipino = tutorialFilipinoCopy.last.body;

    expect(english, contains('sensor status, temperature, rain chance'));
    expect(english, contains('Widgets'));
    expect(english, contains('Tap the widget to open DETECT-CO'));
    expect(filipino, contains('status ng sensor, temperatura'));
    expect(filipino, contains('buksan ang Widgets'));
    expect(filipino, contains('Pindutin ang widget para buksan'));
  });

  testWidgets(
    'tutorial card switches language and exposes navigation actions',
    (tester) async {
      final language = ValueNotifier(TutorialLanguage.english);
      var backCount = 0;
      var nextCount = 0;
      var skipCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TutorialStepCard(
                language: language,
                stepIndex: 1,
                isLast: false,
                canGoBack: true,
                maxHeight: 300,
                onLanguageChanged: (value) => language.value = value,
                onBack: () => backCount++,
                onNext: () => nextCount++,
                onSkip: () => skipCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Flood risk status'), findsOneWidget);
      await tester.tap(find.text('FIL'));
      await tester.pump();
      expect(find.text('Kalagayan ng panganib sa baha'), findsOneWidget);

      await tester.tap(find.text('Bumalik'));
      await tester.tap(find.text('Susunod'));
      await tester.tap(find.text('Laktawan'));
      expect(backCount, 1);
      expect(nextCount, 1);
      expect(skipCount, 1);

      language.dispose();
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(320, 480),
    const Size(568, 320),
    const Size(800, 1280),
  ]) {
    testWidgets(
      'overlay bounds every step and locale at ${size.width}x${size.height}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final language = ValueNotifier(TutorialLanguage.english);
        for (var step = 0; step < tutorialEnglishCopy.length; step++) {
          for (final locale in TutorialLanguage.values) {
            language.value = locale;
            final target = switch (step % 5) {
              0 => Rect.fromLTWH(size.width / 2 - 24, 24, 48, 48),
              1 => Rect.fromLTWH(size.width / 2 - 24, size.height - 72, 48, 48),
              2 => Rect.fromLTWH(0, size.height / 2 - 24, 48, 48),
              3 => Rect.fromLTWH(size.width - 48, size.height / 2 - 24, 48, 48),
              _ => Rect.fromLTWH(
                size.width / 2 - 24,
                size.height / 2 - 24,
                48,
                48,
              ),
            };
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Stack(
                    children: [
                      TutorialCardOverlay(
                        targetRect: target,
                        cardBuilder: (value) => TutorialStepCard(
                          language: language,
                          stepIndex: step,
                          isLast: step == tutorialEnglishCopy.length - 1,
                          canGoBack: step > 0,
                          maxHeight: value.maxHeight,
                          onLanguageChanged: (value) => language.value = value,
                          onBack: () {},
                          onNext: () {},
                          onSkip: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'step $step $locale',
            );
            final cardRect = tester.getRect(find.byType(TutorialStepCard));
            expect(cardRect.left, greaterThanOrEqualTo(0));
            expect(cardRect.right, lessThanOrEqualTo(size.width));
            expect(cardRect.top, greaterThanOrEqualTo(12));
            expect(cardRect.bottom, lessThanOrEqualTo(size.height - 12));
            final nextFinder = find.text(
              locale == TutorialLanguage.english
                  ? (step == tutorialEnglishCopy.length - 1 ? 'Finish' : 'Next')
                  : (step == tutorialEnglishCopy.length - 1
                        ? 'Tapos na'
                        : 'Susunod'),
            );
            expect(nextFinder, findsOneWidget);
            final nextRect = tester.getRect(nextFinder);
            expect(nextRect.top, greaterThanOrEqualTo(cardRect.top));
            expect(nextRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            final skipRect = tester.getRect(
              find.text(
                locale == TutorialLanguage.english ? 'Skip' : 'Laktawan',
              ),
            );
            expect(skipRect.top, greaterThanOrEqualTo(cardRect.top));
            expect(skipRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            if (step > 0) {
              final backRect = tester.getRect(
                find.text(
                  locale == TutorialLanguage.english ? 'Back' : 'Bumalik',
                ),
              );
              expect(backRect.top, greaterThanOrEqualTo(cardRect.top));
              expect(backRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            }
          }
        }
        language.dispose();
      },
    );

    testWidgets(
      'all 21 English and Filipino cards keep controls visible at ${size.width}x${size.height}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final language = ValueNotifier(TutorialLanguage.english);
        var step = 0;
        var skipCount = 0;
        var finishCount = 0;

        Future<void> pumpStep() async {
          final targetCenter = Offset(
            size.width / 2,
            42 + (step * 43) % (size.height - 84),
          );
          final placement = tutorialCardPlacement(
            targetRect: Rect.fromCenter(
              center: targetCenter,
              width: 48,
              height: 48,
            ),
            screenSize: size,
            safeInsets: const EdgeInsets.only(top: 24, bottom: 24),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: TutorialStepCard(
                      language: language,
                      stepIndex: step,
                      isLast: step == tutorialEnglishCopy.length - 1,
                      canGoBack: step > 0,
                      maxHeight: placement.maxHeight,
                      onLanguageChanged: (value) => language.value = value,
                      onBack: () => step--,
                      onNext: () {
                        if (step == tutorialEnglishCopy.length - 1) {
                          finishCount++;
                        } else {
                          step++;
                        }
                      },
                      onSkip: () => skipCount++,
                    ),
                  ),
                ),
              ),
            ),
          );
          final layoutException = tester.takeException();
          expect(
            layoutException,
            isNull,
            reason: 'step $step: $layoutException',
          );
          expect(find.text(tutorialEnglishCopy[step].title), findsOneWidget);
          final nextLabel = step == tutorialEnglishCopy.length - 1
              ? 'Finish'
              : 'Next';
          final nextRect = tester.getRect(find.text(nextLabel));
          expect(nextRect.bottom, lessThanOrEqualTo(size.height - 24));
          expect(nextRect.top, greaterThanOrEqualTo(24));
        }

        await pumpStep();
        await tester.tap(find.text('FIL'));
        await tester.pump();
        expect(find.text(tutorialFilipinoCopy[0].title), findsOneWidget);
        await tester.tap(find.text('EN'));
        await tester.pump();

        for (
          var nextStep = 1;
          nextStep < tutorialEnglishCopy.length;
          nextStep++
        ) {
          await tester.tap(find.text('Next'));
          await tester.pump();
          await pumpStep();
          expect(step, nextStep);
          await tester.tap(find.text('FIL'));
          await tester.pump();
          expect(find.text(tutorialFilipinoCopy[step].title), findsOneWidget);
          await tester.tap(find.text('EN'));
          await tester.pump();
        }

        await tester.tap(find.text('Back'));
        await tester.pump();
        expect(step, tutorialEnglishCopy.length - 2);
        await pumpStep();
        await tester.tap(find.text('Next'));
        await tester.pump();
        await pumpStep();
        await tester.tap(find.text('Finish'));
        expect(finishCount, 1);
        step = 0;
        await pumpStep();
        await tester.tap(find.text('Skip'));
        expect(skipCount, 1);
        language.dispose();
      },
    );
  }
}
