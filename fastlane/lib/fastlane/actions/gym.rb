module Fastlane
  module Actions
    module SharedValues
      IPA_OUTPUT_PATH = :IPA_OUTPUT_PATH
      DSYM_OUTPUT_PATH = :DSYM_OUTPUT_PATH
    end

    class GymAction < Action
      def self.run(values)
        require 'gym'

        values[:export_method] ||= Actions.lane_context[SharedValues::SIGH_PROFILE_TYPE]

        if Actions.lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING]
          # Since Xcode 9 you need to explicitly provide the provisioning profile per app target
          # If the user is smart and uses match and gym together with fastlane, we can do all
          # the heavy lifting for them
          values[:export_options] ||= {}
          # It's not always a hash, because the user might have passed a string path to a ready plist file
          # If that's the case, we won't set the provisioning profiles
          # see https://github.com/fastlane/fastlane/issues/9490
          if values[:export_options].kind_of?(Hash)
            values[:export_options][:provisioningProfiles] = Actions.lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING]
          end
        elsif Actions.lane_context[SharedValues::SIGH_PROFILE_PATHS]
          # Since Xcode 9 you need to explicitly provide the provisioning profile per app target
          # If the user used sigh we can match the profiles from sigh
          values[:export_options] ||= {}
          if values[:export_options].kind_of?(Hash)
            # It's not always a hash, because the user might have passed a string path to a ready plist file
            # If that's the case, we won't set the provisioning profiles
            # see https://github.com/fastlane/fastlane/issues/9684
            values[:export_options][:provisioningProfiles] ||= {}
            Actions.lane_context[SharedValues::SIGH_PROFILE_PATHS].each do |profile_path|
              begin
                profile = FastlaneCore::ProvisioningProfile.parse(profile_path)
                profile_team_id = profile["TeamIdentifier"].first
                next if profile_team_id != values[:export_team_id] && !values[:export_team_id].nil?
                bundle_id = profile["Entitlements"]["application-identifier"].gsub "#{profile_team_id}.", ""
                values[:export_options][:provisioningProfiles][bundle_id] = profile["Name"]
              rescue => ex
                UI.error("Couldn't load profile at path: #{profile_path}")
                UI.error(ex)
                UI.verbose(ex.backtrace.join("\n"))
              end
            end
          end
        end
        absolute_ipa_path = File.expand_path(Gym::Manager.new.work(values))
        absolute_dsym_path = absolute_ipa_path.gsub(".ipa", ".app.dSYM.zip")

        # This might be the mac app path, so we don't want to set it here
        # https://github.com/fastlane/fastlane/issues/5757
        if absolute_ipa_path.include?(".ipa")
          Actions.lane_context[SharedValues::IPA_OUTPUT_PATH] = absolute_ipa_path
          ENV[SharedValues::IPA_OUTPUT_PATH.to_s] = absolute_ipa_path # for deliver
        end

        Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH] = absolute_dsym_path if File.exist?(absolute_dsym_path)
        Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE] = Gym::BuildCommandGenerator.archive_path
        ENV[SharedValues::DSYM_OUTPUT_PATH.to_s] = absolute_dsym_path if File.exist?(absolute_dsym_path)

        return absolute_ipa_path
      end

      def self.description
        "Easily build and sign your app using _gym_"
      end

      def self.details
        "More information: https://fastlane.tools/gym"
      end

      def self.return_value
        "The absolute path to the generated ipa file"
      end

      def self.author
        "KrauseFx"
      end

      def self.available_options
        require 'gym'
        Gym::Options.available_options
      end

      def self.is_supported?(platform)
        [:ios, :mac].include? platform
      end

      def self.example_code
        [
          'gym(scheme: "MyApp", workspace: "MyApp.xcworkspace")',
          'gym(
            workspace: "MyApp.xcworkspace",
            configuration: "Debug",
            scheme: "MyApp",
            silent: true,
            clean: true,
            output_directory: "path/to/dir", # Destination directory. Defaults to current directory.
            output_name: "my-app.ipa",       # specify the name of the .ipa file to generate (including file extension)
            sdk: "10.0"                      # use SDK as the name or path of the base SDK when building the project.
          )'
        ]
      end

      def self.category
        :building
      end
    end
  end
end
