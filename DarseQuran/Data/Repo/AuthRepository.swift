import Foundation

/// Sign-in, sign-out and the signed-in user's own account (Android's AuthRepository).
final class AuthRepository: Sendable {
    private let api: AcademyAPI
    let sessionStore: SessionStore

    init(api: AcademyAPI, sessionStore: SessionStore) {
        self.api = api
        self.sessionStore = sessionStore
    }

    private func signedIn(_ result: ApiResult<TokenResponse>) -> ApiResult<Void> {
        switch result {
        case .success(let tokens): sessionStore.save(tokens); return .success(())
        case .failure(let e): return .failure(e)
        }
    }

    func login(email: String, password: String) async -> ApiResult<Void> {
        signedIn(await apiCall { try await api.login(LoginRequest(email: email.trimmed, password: password)) })
    }

    func register(name: String, email: String, password: String) async -> ApiResult<Void> {
        signedIn(await apiCall { try await api.register(RegisterRequest(name: name.trimmed.nilIfBlank, email: email.trimmed, password: password)) })
    }

    func google(idToken: String) async -> ApiResult<Void> {
        signedIn(await apiCall { try await api.google(GoogleRequest(idToken: idToken)) })
    }

    func forgotPassword(email: String) async -> ApiResult<OkResponse> {
        await apiCall { try await api.forgotPassword(EmailRequest(email: email.trimmed)) }
    }

    func resendVerification(email: String) async -> ApiResult<OkResponse> {
        await apiCall { try await api.resendVerification(EmailRequest(email: email.trimmed)) }
    }

    /// Signs out: tells the server to forget the refresh token (best effort, for at most 5 seconds), then forgets the
    /// session here. Runs to the end even if the screen goes away: leaving mid-way must not leave the user signed in.
    func logout() async {
        let refresh = sessionStore.current?.refreshToken
        let api = self.api
        await Task.detached {
            if let refresh {
                // Offline, the revoke would wait for the connect timeout; signing out shouldn't.
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { _ = await apiCall { try await api.logout(RefreshRequest(refreshToken: refresh)) } }
                    group.addTask { try? await Task.sleep(for: .seconds(5)) }
                    await group.next()
                    group.cancelAll()
                }
            }
        }.value
        sessionStore.clear()
    }

    func profile() async -> ApiResult<Profile> {
        let result = await apiCall { try await api.me().user }
        if case .success(let p) = result { syncSessionUser(p) }
        return result
    }

    func updateProfile(_ update: ProfileUpdate) async -> ApiResult<Profile> {
        let result = await apiCall { try await api.updateProfile(update).user }
        if case .success(let p) = result { syncSessionUser(p) }
        return result
    }

    func uploadPhoto(_ data: Data, mime: String) async -> ApiResult<String?> {
        await apiCall { try await api.uploadPhoto(FilePart(name: "image", filename: "photo.jpg", mimeType: mime, data: data)).image }
    }

    func removePhoto() async -> ApiResult<String?> { await apiCall { try await api.removePhoto().image } }

    func changePassword(current: String, new: String) async -> ApiResult<OkResponse> {
        await apiCall { try await api.changePassword(ChangePasswordRequest(currentPassword: current, newPassword: new)) }
    }

    /// Deletes the account; [beforeSignOut] runs once the server has deleted it, before the session here is cleared.
    func deleteAccount(password: String?, confirm: String?, beforeSignOut: () -> Void = {}) async -> ApiResult<Void> {
        switch await apiCall({ try await api.deleteAccount(DeleteAccountRequest(password: password, confirm: confirm)) }) {
        case .success: beforeSignOut(); sessionStore.clear(); return .success(())
        case .failure(let e): return .failure(e)
        }
    }

    private func syncSessionUser(_ profile: Profile) {
        sessionStore.updateUser(SessionUser(
            id: profile.id, email: profile.email, name: profile.name, image: profile.image,
            role: profile.role, registrationNumber: profile.registrationNumber
        ))
    }
}
