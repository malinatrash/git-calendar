#!/usr/bin/env ruby

require "xcodeproj"
require "fileutils"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "GitCalendar.xcodeproj")
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2630"
project.root_object.attributes["LastUpgradeCheck"] = "2630"

project.build_configurations.each do |configuration|
  configuration.build_settings.merge!(
    "MACOSX_DEPLOYMENT_TARGET" => "14.0",
    "SDKROOT" => "macosx",
    "SWIFT_VERSION" => "5.0",
    "CLANG_ENABLE_MODULES" => "YES",
    "SWIFT_STRICT_CONCURRENCY" => "targeted"
  )
end

app = project.new_target(:application, "GitCalendar", :osx, "14.0", nil, :swift)
widget = project.new_target(:app_extension, "GitCalendarWidget", :osx, "14.0", nil, :swift)
tests = project.new_target(:unit_test_bundle, "GitCalendarTests", :osx, "14.0", nil, :swift)

def configure_target(target, settings)
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!(settings)
  end
end

common = {
  "SWIFT_VERSION" => "5.0",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "CODE_SIGN_STYLE" => "Automatic",
  "CURRENT_PROJECT_VERSION" => "2",
  "MARKETING_VERSION" => "1.0.1",
  "ENABLE_HARDENED_RUNTIME" => "YES"
}

configure_target(app, common.merge(
  "PRODUCT_BUNDLE_IDENTIFIER" => "io.github.malinatrash.GitCalendar",
  "PRODUCT_NAME" => "GitCalendar",
  "INFOPLIST_FILE" => "GitCalendarApp/Info.plist",
  "CODE_SIGN_ENTITLEMENTS" => "GitCalendarApp/GitCalendar.entitlements",
  "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
  "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME" => "AccentColor",
  "ENABLE_APP_SANDBOX" => "NO"
))

configure_target(widget, common.merge(
  "PRODUCT_BUNDLE_IDENTIFIER" => "io.github.malinatrash.GitCalendar.Widget",
  "PRODUCT_NAME" => "GitCalendarWidget",
  "INFOPLIST_FILE" => "GitCalendarWidget/Info.plist",
  "CODE_SIGN_ENTITLEMENTS" => "GitCalendarWidget/GitCalendarWidget.entitlements",
  "APPLICATION_EXTENSION_API_ONLY" => "YES",
  "SKIP_INSTALL" => "YES"
))

configure_target(tests, {
  "PRODUCT_BUNDLE_IDENTIFIER" => "io.github.malinatrash.GitCalendarTests",
  "GENERATE_INFOPLIST_FILE" => "YES",
  "SWIFT_VERSION" => "5.0",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "CODE_SIGNING_ALLOWED" => "NO"
})

groups = {}
%w[GitCalendarShared GitCalendarApp GitCalendarWidget GitCalendarTests].each do |name|
  groups[name] = project.main_group.new_group(name, name)
end

def refs_for(group, paths)
  paths.map { |path| group.new_file(path) }
end

shared_refs = refs_for(groups["GitCalendarShared"], %w[Models.swift SharedStore.swift CalendarSupport.swift])
app_refs = refs_for(groups["GitCalendarApp"], [
  "GitCalendarApp.swift",
  "AppState.swift",
  "GitScanner.swift",
  "MetricEngine.swift",
  "UpdateChecker.swift",
  "DesignSystem.swift",
  "Views/ContentView.swift",
  "Views/CalendarEditorView.swift",
  "Views/DashboardView.swift",
  "Views/DayDetailView.swift"
])
widget_refs = refs_for(groups["GitCalendarWidget"], %w[WidgetIntent.swift GitCalendarWidget.swift GitCalendarWidgetBundle.swift])
test_refs = refs_for(groups["GitCalendarTests"], %w[MetricEngineTests.swift GitLogParserTests.swift GitScannerIntegrationTests.swift UpdateCheckerTests.swift])

app.add_file_references(shared_refs + app_refs)
assets_ref = groups["GitCalendarApp"].new_file("Assets.xcassets")
app.add_resources([assets_ref])
widget.add_file_references(shared_refs + widget_refs)
tests.add_file_references(shared_refs + [app_refs[2], app_refs[3], app_refs[4]] + test_refs)

app.add_dependency(widget)
embed_phase = app.new_copy_files_build_phase("Embed Foundation Extensions")
embed_phase.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_phase.add_file_reference(widget.product_reference, true)
build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(widget)
scheme.add_build_target(tests, false)
scheme.add_test_target(tests)
scheme.set_launch_target(app)

project.save
scheme.save_as(project_path, "GitCalendar", true)

puts "Generated #{project_path}"
