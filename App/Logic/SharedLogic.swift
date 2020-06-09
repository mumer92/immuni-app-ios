// SharedLogic.swift
// Copyright (C) 2020 Presidenza del Consiglio dei Ministri.
// Please refer to the AUTHORS file for more information.
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import Extensions
import Hydra
import Katana
import Models
import Tempura

extension Logic {
  enum Shared {}
}

extension Logic.Shared {
  /// Handle interaction when user taps on a push notification.
  struct HandleNotificationResponse: AppSideEffect {
    let requestNotificationID: String

    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      if Logic.ForceUpdate.forceUpdateNotificationIDs.contains(self.requestNotificationID) {
        context.dispatch(OpenAppStorePage())
      }

      if Logic.CovidStatus.covidNotificationIDs.contains(self.requestNotificationID) {
        context.dispatch(HandleContactNotification())
      }
    }
  }

  /// Open AppStore page of the application
  struct OpenAppStorePage: AppSideEffect {
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      let appRelativeUrl = context.dependencies.bundle.appStoreID.flatMap { "app/id" + $0 } ?? ""
      guard let url = URL(string: "https://itunes.apple.com/\(appRelativeUrl)") else {
        return
      }

      try await(context.dependencies.application.goTo(url: url))
    }
  }

  /// Open an URL in Safari or default browser.
  struct OpenURL: AppSideEffect {
    let url: URL
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      try await(context.dependencies.application.goTo(url: self.url))
    }
  }

  /// Update selected tab of the tabbar during this session.
  struct UpdateSelectedTab: AppStateUpdater {
    let tab: TabbarVM.Tab

    func updateState(_ state: inout AppState) {
      guard state.environment.selectedTab != self.tab else {
        return
      }

      state.environment.selectedTab = self.tab
    }
  }

  /// Show sensitive data cover.
  struct ShowSensitiveDataCoverIfNeeded: AppSideEffect {
    /// The list of screens that can present the cover.
    static let possiblePresenters: [String] = [Screen.tabBar.rawValue, Screen.onboardingStep.rawValue]
    /// The list of screens that, if present, will block the presentation of a cover.
    static let possibleBlockers: [String] = [
      // avoid double presentation
      Screen.sensitiveDataCover.rawValue,
      // avoid when a native alert presentation is needed
      Screen.permissionOverlay.rawValue
    ]

    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      guard
        context.dependencies.application.currentRoutableIdentifiers
        .contains(where: { Self.possiblePresenters.contains($0) }) else {
          return
      }
      guard
        !context.dependencies.application.currentRoutableIdentifiers
        .contains(where: { Self.possibleBlockers.contains($0) }) else {
          return
      }

      context.dispatch(Show(Screen.sensitiveDataCover, animated: false))
    }
  }

  /// Hide sensitive data cover.
  struct HideSensitiveDataCoverIfPresent: AppSideEffect {
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      guard context.dependencies.application.currentRoutableIdentifiers.contains(Screen.sensitiveDataCover.rawValue) else {
        return
      }
      context.dispatch(Hide(Screen.sensitiveDataCover, animated: false))
    }
  }

  /// Opens App's settings page in the native setting app
  struct OpenSettings: AppSideEffect {
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        return
      }

      try await(context.dependencies.application.goTo(url: url).run())
    }
  }

  /// Opens an external link using `UIApplication`
  struct OpenExternalLink: AppSideEffect {
    let url: URL

    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      _ = context.dependencies.application.goTo(url: self.url).run()
    }
  }

  /// This action preloads all the Lottie Animation structs. This is done as a workaround for the performance regression on
  /// Lottie 3 ( https://github.com/airbnb/lottie-ios/issues/895 ).
  /// Most of the issue is due to the serialization of the Lottie JSON and this action prevents the app to perform this
  /// serialization multiple times as the used `animation` property in `AnimationAsset` are statically allocated.
  /// The issue is particularly evident in collection views with multiple animations in multiple cells.
  struct PreloadAssets: AppSideEffect {
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      _ = AnimationAsset.allCases.map { $0.animation }
    }
  }
}

// MARK: - Private

private extension Logic.Shared {
  /// Handle contact notification opened. This action will present the Suggestion view from the home tab.
  /// The action will aumatically wait for the app setup to be completed before showing the suggestions view.
  struct HandleContactNotification: AppSideEffect {
    func sideEffect(_ context: SideEffectContext<AppState, AppDependencies>) throws {
      // wait for the tabbar to be shown. Note that this check will survive until
      // the app is killed.
      try context.awaitDispatch(WaitForState(closure: { _ -> Bool in
        context.dependencies.application.currentRoutableIdentifiers
          .contains(Screen.tabBar.rawValue)
      }))

      // move to home tab and show suggestions view.
      try context.awaitDispatch(Logic.Shared.UpdateSelectedTab(tab: .home))
      try context.awaitDispatch(Logic.Suggestions.ShowSuggestions())
    }
  }
}
