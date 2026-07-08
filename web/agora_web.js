// Agora Web SDK bridge for Flutter
// Manages a single video call session

window.agoraWeb = {
  client: null,
  localAudioTrack: null,
  localVideoTrack: null,
  _onUserJoined: null,
  _onUserLeft: null,
  _onJoined: null,
  _onError: null,

  selectedMicId: null,
  selectedCameraId: null,
  selectedSpeakerId: null,

  async listDevices() {
    try {
      const [mics, cams, speakers] = await Promise.all([
        AgoraRTC.getMicrophones(),
        AgoraRTC.getCameras(),
        AgoraRTC.getPlaybackDevices(),
      ]);
      return JSON.stringify({
        microphones: mics.map(d => ({ id: d.deviceId, name: d.label || "Mikrofon" })),
        cameras: cams.map(d => ({ id: d.deviceId, name: d.label || "Kamera" })),
        speakers: speakers.map(d => ({ id: d.deviceId, name: d.label || "Høyttaler" })),
        selected: {
          microphone: this.selectedMicId,
          camera: this.selectedCameraId,
          speaker: this.selectedSpeakerId,
        },
      });
    } catch (e) {
      console.error("Agora listDevices error:", e);
      return JSON.stringify({ microphones: [], cameras: [], speakers: [], selected: {} });
    }
  },

  async setMicrophone(deviceId) {
    try {
      this.selectedMicId = deviceId;
      if (this.localAudioTrack) {
        await this.localAudioTrack.setDevice(deviceId);
      }
      return true;
    } catch (e) {
      console.error("Agora setMicrophone error:", e);
      return false;
    }
  },

  async setCamera(deviceId) {
    try {
      this.selectedCameraId = deviceId;
      if (this.localVideoTrack) {
        await this.localVideoTrack.setDevice(deviceId);
      }
      return true;
    } catch (e) {
      console.error("Agora setCamera error:", e);
      return false;
    }
  },

  async setSpeaker(deviceId) {
    try {
      this.selectedSpeakerId = deviceId;
      if (this.client && this.client.remoteUsers) {
        for (const user of this.client.remoteUsers) {
          if (user.audioTrack && user.audioTrack.setPlaybackDevice) {
            try { await user.audioTrack.setPlaybackDevice(deviceId); } catch (_) {}
          }
        }
      }
      return true;
    } catch (e) {
      console.error("Agora setSpeaker error:", e);
      return false;
    }
  },

  async init(appId, channelName, token, uid) {
    try {
      this.client = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });

      this.client.on("user-published", async (user, mediaType) => {
        await this.client.subscribe(user, mediaType);
        if (mediaType === "video") {
          const playRemote = (attempts) => {
            const container = document.getElementById("agora-remote-" + user.uid);
            if (container) {
              user.videoTrack.play(container);
              return;
            }
            const remoteArea = document.getElementById("agora-remote-area");
            if (remoteArea) {
              const div = document.createElement("div");
              div.id = "agora-remote-" + user.uid;
              div.style.width = "100%";
              div.style.height = "100%";
              remoteArea.appendChild(div);
              user.videoTrack.play(div);
            } else if (attempts > 0) {
              setTimeout(() => playRemote(attempts - 1), 200);
            }
          };
          playRemote(15);
        }
        if (mediaType === "audio") {
          if (this.selectedSpeakerId && user.audioTrack.setPlaybackDevice) {
            try { await user.audioTrack.setPlaybackDevice(this.selectedSpeakerId); } catch (_) {}
          }
          user.audioTrack.play();
        }
        if (this._onUserJoined) this._onUserJoined(user.uid.toString());
      });

      this.client.on("user-unpublished", (user, mediaType) => {
        if (mediaType === "video") {
          const container = document.getElementById("agora-remote-" + user.uid);
          if (container) container.innerHTML = "";
        }
      });

      this.client.on("user-left", (user) => {
        const container = document.getElementById("agora-remote-" + user.uid);
        if (container) container.remove();
        if (this._onUserLeft) this._onUserLeft(user.uid.toString());
      });

      // Get media tracks (use saved device IDs if set)
      const audioCfg = this.selectedMicId ? { microphoneId: this.selectedMicId } : {};
      const videoCfg = this.selectedCameraId ? { cameraId: this.selectedCameraId } : {};
      [this.localAudioTrack, this.localVideoTrack] =
        await AgoraRTC.createMicrophoneAndCameraTracks(audioCfg, videoCfg);

      // Join
      const joinedUid = await this.client.join(appId, channelName, token, uid || null);

      // Publish
      await this.client.publish([this.localAudioTrack, this.localVideoTrack]);

      // Play local video (retry — Flutter may not have added the platform view yet)
      const playLocal = (attempts) => {
        const el = document.getElementById("agora-local-video");
        if (el) {
          this.localVideoTrack.play(el);
        } else if (attempts > 0) {
          setTimeout(() => playLocal(attempts - 1), 200);
        }
      };
      playLocal(15);

      if (this._onJoined) this._onJoined(joinedUid.toString());
      return true;
    } catch (e) {
      console.error("Agora web init error:", e);
      if (this._onError) this._onError(e.message || String(e));
      return false;
    }
  },

  async leave() {
    try {
      if (this.localAudioTrack) {
        this.localAudioTrack.close();
        this.localAudioTrack = null;
      }
      if (this.localVideoTrack) {
        this.localVideoTrack.close();
        this.localVideoTrack = null;
      }
      if (this.client) {
        await this.client.leave();
        this.client = null;
      }
    } catch (e) {
      console.error("Agora leave error:", e);
    }
  },

  muteAudio(muted) {
    if (this.localAudioTrack) {
      this.localAudioTrack.setEnabled(!muted);
    }
  },

  muteVideo(muted) {
    if (this.localVideoTrack) {
      this.localVideoTrack.setEnabled(!muted);
    }
  },

  getRemoteUsers() {
    if (!this.client) return [];
    return this.client.remoteUsers.map(u => u.uid.toString());
  }
};
