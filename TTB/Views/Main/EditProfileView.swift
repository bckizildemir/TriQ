import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ProfileModel
    var actionsDisabled: Bool = false
    var onDeleteAccount: (() -> Void)?

    @State private var tempUsername: String = ""
    @State private var tempEmail: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "profile.edit.usernamePlaceholder"), text: $tempUsername)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .accessibilityLabel(String(localized: "profile.edit.usernameAccessibility"))
                        .dynamicTypeSize(.large ... .accessibility5)
                    
                    TextField(String(localized: "profile.edit.emailPlaceholder"), text: $tempEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .accessibilityLabel(String(localized: "profile.edit.emailAccessibility"))
                        .dynamicTypeSize(.large ... .accessibility5)
                }
                
                Section {
                    Button {
                        model.showingImagePicker = true
                    } label: {
                        HStack {
                            Text(String(localized: "profile.edit.changePhoto"))
                            Spacer()
                            Image(systemName: "camera.fill")
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "profile.edit.changePhotoAccessibility"))
                    .accessibilityHint(String(localized: "profile.edit.changePhotoHint"))
                }

                if onDeleteAccount != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Text(String(localized: "profile.settings.deleteAccount"))
                                Spacer()
                                Image(systemName: "trash")
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .disabled(actionsDisabled)
                    }
                }
            }
            .navigationTitle(String(localized: "profile.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SimulatorSafeSheetDismissButton {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(String(localized: "profile.edit.cancelAccessibility"))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            model.username = tempUsername
                            model.email = tempEmail
                            await model.updateProfile()
                            guard !model.showingAlert else { return }
                            if model.tempImage != nil {
                                await model.updateProfileImage()
                            }
                            guard !model.showingAlert else { return }
                            dismiss()
                        }
                    } label: {
                        Label(String(localized: "common.save"), systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(String(localized: "profile.edit.saveAccessibility"))
                }
            }
            .onAppear {
                tempUsername = model.username
                tempEmail = model.email
            }
            .photosPicker(isPresented: $model.showingImagePicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                    // Downsample at ingestion so the form never holds a full-resolution bitmap:
                    // this image is uploaded at 800 px and shown in a 100 pt circle.
                    let image = await Task.detached(priority: .userInitiated) {
                        DownsampledImageDecoder.image(from: data)
                    }.value
                    if let image {
                        model.tempImage = image
                    }
                }
            }
            .alert(String(localized: "common.error.title"), isPresented: $model.showingAlert) {
                Button(String(localized: "common.ok"), role: .cancel) { }
            } message: {
                Text(model.alertMessage)
            }
            .confirmationDialog(String(localized: "profile.deleteAccount.title"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button(String(localized: "profile.deleteAccount.confirm"), role: .destructive) {
                    onDeleteAccount?()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "profile.deleteAccount.message"))
            }
        }
    }
}

#Preview {
    EditProfileView(model: ProfileModel(userId: "preview"))
}
