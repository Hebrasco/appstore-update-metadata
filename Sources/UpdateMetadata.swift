//
//  main.swift
//  appstore-update-metadata
//
//  Created by Daniel Bedrich on 08.02.26.
//

import Foundation
import ArgumentParser
@preconcurrency import AppStoreConnect_Swift_SDK

let provider = APIProvider(configuration: APPSTORE_CONFIGURATION)

@main
struct UpdateMetadata: AsyncParsableCommand {
    @Argument(help: "The path to the folder where the '.json' files are.")
    var localizationsPath: String
    
    @Option(name: .long, help: "The bundle id of the app to update the metadata for.")
    var bundleId: String

    mutating func run() async throws {
        await updateMetadata(forBundleId: bundleId)
    }
    
    func updateMetadata(forBundleId bundleId: String) async {
        let app = await requestApp(bundleId: bundleId)
        let version = await requestLatestAppVersion(app)
        let localizations = version.relationships!.appStoreVersionLocalizations!.data!
        
        for localizationId in localizations.map({ $0.id }) {
            let localization = await requestLocalization(localizationId)
            let appStoreLocale = localization.attributes!.locale!
            let fileManager = FileManager.default
            let doesAppStoreLocaleFileExist = fileManager.fileExists(atPath: "\(localizationsPath)/\(appStoreLocale).json")
            
            let backupLocale = getBackupLocale(appStoreLocale)
            let doesBackupLocaleFileExist = fileManager.fileExists(atPath: "\(localizationsPath)/\(backupLocale).json")

            var locale: String? {
                if doesAppStoreLocaleFileExist { return appStoreLocale }
                if doesBackupLocaleFileExist { return backupLocale }
                return nil
            }
            
            guard let locale else {
                print("No localization file found for '\(appStoreLocale).json' or '\(backupLocale).json'. Continuing")
                
                continue
            }
            
            print("🌐 Updating \(appStoreLocale)")
            
            let url = URL(string: "file://\(localizationsPath)/\(locale).json")
            guard let url else { UpdateMetadata.exit() }
            
            let jsonData = try! Data(contentsOf: url)
            let attributes = try! JSONDecoder().decode(
                AppStoreVersionLocalizationUpdateRequest.Data.Attributes.self,
                from: jsonData
            )
            
            let isDescriptionValid = validateAttribute(attributes.description, maxCount: 4000)
            let isKeywordsValid = validateAttribute(attributes.keywords, maxCount: 100)
            let isPromotionalTextValid = validateAttribute(attributes.promotionalText, maxCount: 170)
            let isWhatsNewValid = validateAttribute(attributes.whatsNew, maxCount: 4000)
            
            if !isDescriptionValid { print("The attribute 'description' is longer than 4000 characters.") }
            if !isKeywordsValid { print("The attribute 'keywords' is longer than 100 characters.") }
            if !isPromotionalTextValid { print("The attribute 'promotionalText' is longer than 170 characters.") }
            if !isWhatsNewValid { print("The attribute 'whatsNew' is longer than 4000 characters.") }
            
            if
                !isDescriptionValid ||
                !isKeywordsValid ||
                !isPromotionalTextValid ||
                !isWhatsNewValid
            {
                print("Some attributes are invalid. Continuing...")
                
                continue
            }

            let _ = await requestUpdateLocalization(localizationId, attributes: attributes)
        }
        
    }
    
    func getBackupLocale(_ locale: String) -> String {
        if locale == "no" { return "nb" }
        
        return String(locale.split(separator: "-").first ?? "")
    }
    
    func validateAttribute(_ attribute: String?, maxCount: Int) -> Bool {
        attribute?.count ?? 0 <= maxCount
    }

    func requestApp(bundleId: String) async -> App {
        let appRequest = APIEndpoint.v1
            .apps
            .get(parameters: .init(filterBundleID: [bundleId], include: [.appInfos, .appStoreVersions]))
        let app: App = try! await provider.request(appRequest).data.first!
        
        return app
    }
    
    func requestLatestAppVersion(_ app: App) async -> AppStoreVersion {
        let versionId = app.relationships!.appStoreVersions!.data!.first!.id
        let versionRequest = APIEndpoint.v1
            .appStoreVersions
            .id(versionId)
            .get(parameters: .init(include: [.appStoreVersionLocalizations], limitAppStoreVersionLocalizations: 50))
        let version: AppStoreVersion = try! await provider.request(versionRequest).data
        
        return version
    }
    
    func requestLocalization(_ id: String) async -> AppStoreVersionLocalization {
        let localizationRequest = APIEndpoint.v1
            .appStoreVersionLocalizations
            .id(id)
            .get()
        let localization: AppStoreVersionLocalization = try! await provider.request(localizationRequest).data
        
        return localization
    }
    
    func requestUpdateLocalization(_ id: String, attributes: AppStoreVersionLocalizationUpdateRequest.Data.Attributes) async -> AppStoreVersionLocalization {
        let updateLocalizationRequest = APIEndpoint.v1
            .appStoreVersionLocalizations
            .id(id)
            .patch(.init(data: .init(type: .appStoreVersionLocalizations, id: id, attributes: attributes)))
        let localization: AppStoreVersionLocalization = try! await provider.request(updateLocalizationRequest).data
        
        return localization
    }
}
