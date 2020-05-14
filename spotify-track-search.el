;; spotify-track-search.el --- Spotify.el track search major mode

;; Copyright (C) 2014-2018 Daniel Fernandes Martins

;; Code:

(require 'spotify-api)

;; Internal.
(defvar helm-tracks-doc-header
  " (\\<helm-tracks-map>\\[helm-tracks-load-more-interactive]: Load more tracks)"
  "*The doc that is inserted in the Name header of the helm spotify source.")

(defun helm-tracks-load-more-interactive ()
  " Helm action to load more tracks "
  (interactive)
  (with-helm-alive-p
    (helm-exit-and-execute-action 'helm-tracks-load-more-core)))

(defun helm-tracks-load-more-core (_candidate)
  " Helm action to load more tracks "
  (spotify-track-load-more))

(defcustom helm-tracks-actions (helm-make-actions
                                "Play track `RET'" 'spotify-track-select-default
                                "Load more tracks `C-l'" 'helm-tracks-load-more-core)
  "Actions for tracks in helm buffers"
  :group 'spotify
  :type '(alist :key-type string :value-type function))

(defvar helm-tracks-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-l") 'helm-tracks-load-more-interactive)
    map)
  "Local keymap for tracks in helm buffers")

(defvar spotify-track-search-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "M-RET") 'spotify-track-select)
    (define-key map (kbd "a")     'spotify-track-add)
    (define-key map (kbd "l")     'spotify-track-load-more)
    (define-key map (kbd "g")     'spotify-track-reload)
    (define-key map (kbd "f")     'spotify-track-playlist-follow)
    (define-key map (kbd "u")     'spotify-track-playlist-unfollow)
    map)
  "Local keymap for `spotify-track-search-mode' buffers.")

;; Enables the `spotify-remote-mode' the track search buffer
(add-hook 'spotify-track-search-mode-hook 'spotify-remote-mode)

(define-derived-mode spotify-track-search-mode tabulated-list-mode "Track-Search"
  "Major mode for displaying the track listing returned by a Spotify search.")

(defun spotify-track-select ()
  "Plays the track, album or artist under the cursor. If the cursor is on a
button representing an artist or album, start playing that artist or album.
Otherwise, play the track selected."
  (interactive)
  (let ((button-type (spotify-track-selected-button-type)))
    (cond ((eq 'artist button-type)
	   (spotify-track-artist-select))
	  ((eq 'album button-type)
	   (spotify-track-album-select))
	  (t (spotify-track-select-default)))))

(defun spotify-track-select-default (&optional helm-selection-id)
  "Plays the track under the cursor. If the track list represents a playlist,
the given track is played in the context of that playlist; if the track list
represents an album, the given track is played in the context of that album;
otherwise, it will be played without a context."
  (interactive)
  (let* ((track (or helm-selection-id (tabulated-list-get-id)))
         (context (cond ((bound-and-true-p spotify-selected-playlist) spotify-selected-playlist)
                        ((bound-and-true-p spotify-selected-album) spotify-selected-album)
                        (t nil))))
    (spotify-play-track track context)))

(defun spotify-track-selected-button-type ()
  (let ((selected-button (button-at (point))))
    (when selected-button
      (button-get selected-button 'artist-or-album))))

(defun spotify-track-artist-select ()
  "Plays the artist of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (artist (spotify-get-track-artist track)))
    (spotify-play-track track artist)))

(defun spotify-track-album-select ()
  "Plays the album of the track under the cursor."
  (interactive)
  (let* ((track (tabulated-list-get-id))
         (album (spotify-get-track-album track)))
    (spotify-play-track track album)))

(defun spotify-track-playlist-follow ()
  "Adds the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p spotify-selected-playlist)
      (lexical-let ((playlist spotify-selected-playlist))
        (when (y-or-n-p (format "Follow playlist '%s'?" (spotify-get-item-name playlist)))
          (spotify-api-playlist-follow
           playlist
           (lambda (_)
             (message (format "Followed playlist '%s'" (spotify-get-item-name playlist)))))))
    (message "Cannot Follow a playlist from here")))

(defun spotify-track-playlist-unfollow ()
  "Removes the current user as the follower of the selected playlist."
  (interactive)
  (if (bound-and-true-p spotify-selected-playlist)
      (lexical-let ((playlist spotify-selected-playlist))
        (when (y-or-n-p (format "Unfollow playlist '%s'?" (spotify-get-item-name playlist)))
          (spotify-api-playlist-unfollow
           playlist
           (lambda (_)
             (message (format "Unfollowed playlist '%s'" (spotify-get-item-name playlist)))))))
    (message "Cannot unfollow a playlist from here")))

(defun spotify-track-reload ()
  "Reloads the first page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p spotify-recently-played)
         (spotify-recently-played-tracks-update 1))
        ((bound-and-true-p spotify-selected-playlist)
         (spotify-playlist-tracks-update 1))
        ((bound-and-true-p spotify-query)
         (spotify-track-search-update spotify-query 1))
        ((bound-and-true-p spotify-selected-album)
         (spotify-album-tracks-update spotify-selected-album 1))))

(defun spotify-track-load-more ()
  "Loads the next page of results for the current track view."
  (interactive)
  (cond ((bound-and-true-p spotify-recently-played)
         (spotify-recently-played-tracks-update (1+ spotify-current-page)))
        ((bound-and-true-p spotify-selected-playlist)
         (if (eq tracks-loaded total-tracks)
             (spotify-playlist-tracks-update spotify-current-page)
           (spotify-playlist-tracks-update (1+ spotify-current-page))))
        ((bound-and-true-p spotify-selected-album)
         (spotify-album-tracks-update spotify-selected-album (1+ spotify-current-page)))
        ((bound-and-true-p spotify-query)
         (spotify-track-search-update spotify-query (1+ spotify-current-page)))))

(defun helm-source-tracks-from-current-buffer (source-name)
  "Available only if helm integration is enabled & helm is installed
This will use the tab buffer generated as a source for helm to operate on"
  (lexical-let ((tabulated-list-entries tabulated-list-entries))
    (helm :sources (helm-build-in-buffer-source source-name
                     :header-name (lambda (name)
                         (concat name (substitute-command-keys helm-tracks-doc-header)))
                     :data (current-buffer)
                     :get-line #'buffer-substring
                     :display-to-real (lambda (_candidate)
                                        (let* ((candidate
                                                (helm-get-selection nil 'withprop))
                                               (tabulated-list-id
                                                (get-text-property 0 'tabulated-list-id candidate)))
                                          tabulated-list-id))
                     :action helm-tracks-actions
                     :keymap helm-tracks-map
                     :fuzzy-match t)
          :buffer "*helm spotify*")))

(defun spotify-track-search-update (query current-page)
  "Fetches the given page of results using the search endpoint."
  (lexical-let ((current-page current-page)
                (query query)
                (buffer (current-buffer)))
    (spotify-api-search
     'track
     query
     current-page
     (lambda (json)
       (if-let ((items (spotify-get-search-track-items json)))
           (with-current-buffer buffer
             (setq-local spotify-current-page current-page)
             (setq-local spotify-query query)
             (if (and spotify-helm-integration (package-installed-p 'helm))
                 (progn
                   (spotify-track-search-print items current-page)
                   (helm-source-tracks-from-current-buffer
                    (format "Spotify Tracks - Search Results for \"%s\"" query)))
               (pop-to-buffer buffer)
               (spotify-track-search-print items current-page)
               (message "Track view updated")))
         (message "No more tracks"))))))

(defun spotify-playlist-tracks-update (current-page)
  "Fetches the given page of results for the current playlist."
  (when (bound-and-true-p spotify-selected-playlist)
    (lexical-let ((current-page current-page)
                  (buffer (current-buffer)))
      (spotify-api-playlist-tracks
       spotify-selected-playlist
       current-page
       (lambda (json)
         (if-let ((items (spotify-get-playlist-tracks json)))
             (with-current-buffer buffer
               (setq-local spotify-current-page current-page)
               (if (and spotify-helm-integration (package-installed-p 'helm))
                   (progn
                     (setq-local current-page-size (length (gethash 'items json)))
                     (setq-local tracks-loaded (+ (* 50 (1- current-page)) current-page-size))
                     (setq-local total-tracks (gethash 'total json))
                     (spotify-track-search-print items current-page)
                     (helm-source-tracks-from-current-buffer
                      (format "%s (%s/%s tracks loaded)"
                              (gethash 'name spotify-selected-playlist)
                              tracks-loaded
                              total-tracks)))
                 (pop-to-buffer buffer)
                 (spotify-track-search-print items current-page)
                 (message "Track view updated")))
           (message "No more tracks")))))))

(defun spotify-album-tracks-update (album current-page)
  "Fetches the list of tracks for the given album."
  (lexical-let ((album album)
                (current-page current-page)
                (buffer (current-buffer)))
    (spotify-api-album-tracks
     album
     current-page
     (lambda (json)
       (if-let ((items (spotify-get-items json)))
           (with-current-buffer buffer
             (setq-local spotify-current-page current-page)
             (setq-local spotify-selected-album album)
             (pop-to-buffer buffer)
             (spotify-track-search-print items current-page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun spotify-recently-played-tracks-update (current-page)
  "Fetches the given page of results for the recently played tracks."
  (lexical-let ((current-page current-page)
                (buffer (current-buffer)))
    (spotify-api-recently-played
     current-page
     (lambda (json)
       (if-let ((items (spotify-get-playlist-tracks json)))
           (with-current-buffer buffer
             (setq-local spotify-current-page current-page)
             (setq-local spotify-recently-played t)
             (pop-to-buffer buffer)
             (spotify-track-search-print items current-page)
             (message "Track view updated"))
         (message "No more tracks"))))))

(defun spotify-track-search-set-list-format ()
  "Configures the column data for the typical track view. The tracks are sorted by number by default when listing the tracks from an album."
  (let* ((base-width (truncate (/ (- (window-width) 30) 3)))
         (default-width (if (bound-and-true-p spotify-selected-album) (+ base-width 4) base-width )))
    (when (not (bound-and-true-p spotify-selected-playlist))
        (setq tabulated-list-sort-key `("#" . nil)))
    (setq tabulated-list-format
          (vconcat (vector `("#" 3 ,(lambda (row-1 row-2)
                            (< (+ (* 100 (spotify-get-disc-number (first row-1)))
                                  (spotify-get-track-number (first row-1)))
                               (+ (* 100 (spotify-get-disc-number (first row-2)))
                                  (spotify-get-track-number (first row-2))))) :right-align t)
                           `("Track Name" ,default-width t)
                           `("Artist" ,default-width t)
                           `("Album" ,default-width t)
                           `("Time" 8 (lambda (row-1 row-2)
                                        (< (spotify-get-track-duration (first row-1))
                                           (spotify-get-track-duration (first row-2))))))
                   (when (not (bound-and-true-p spotify-selected-album))
                     (vector '("Popularity" 14 t)))))))

(defun spotify-track-search-print (songs current-page)
  "Appends the given songs to the current track view."
  (let (entries)
    (dolist (song songs)
      (when (spotify-is-track-playable song)
        (let* ((artist-name (spotify-get-track-artist-name song))
               (album (or (spotify-get-track-album song) spotify-selected-album))
               (album-name (spotify-get-item-name album))
               (album (spotify-get-track-album song)))
          (push (list song
                      (vector (number-to-string (spotify-get-track-number song))
                              (spotify-get-item-name song)
                              (cons artist-name
                                  (list 'face 'link
                                        'follow-link t
                                        'action `(lambda (_) (spotify-track-search ,(format "artist:\"%s\"" artist-name)))
                                        'help-echo (format "Show %s's tracks" artist-name)
					'artist-or-album 'artist))
                              (cons album-name
                                  (list 'face 'link
                                        'follow-link t
                                        'action `(lambda (_) (spotify-album-tracks ,album))
                                        'help-echo (format "Show %s's tracks" album-name)
					'artist-or-album 'album))
                              (spotify-get-track-duration-formatted song)
                              (when (not (bound-and-true-p spotify-selected-album))
                                (spotify-popularity-bar (spotify-get-track-popularity song)))))
                entries))))
    (spotify-track-search-set-list-format)
    (when (eq 1 current-page) (setq-local tabulated-list-entries nil))
    (setq-local tabulated-list-entries (append tabulated-list-entries (nreverse entries)))
    (tabulated-list-init-header)
    (tabulated-list-print t)))

(defun spotify-album-tracks (album)
  "Open a new buffer that lists the tracks from the given album."
  (let ((buffer (get-buffer-create (format "*Album: %s*" (spotify-get-item-name album)))))
    (with-current-buffer buffer
      (spotify-track-search-mode)
      (spotify-album-tracks-update album 1))))

(defun spotify-select-playlist (callback)
  "Ask the user to select a playlist and calls CALLBACK with the selected option."
  (interactive)
  (lexical-let ((callback callback))
    (spotify-current-user
     (lambda (user)
       (spotify-api-user-playlists
        (spotify-get-item-id user)
        1
        (lambda (json)
          (if-let* ((choices (mapcar (lambda (a)
                                       (list (spotify-get-item-name a) (spotify-get-item-id a)))
                                     (spotify-get-items json)))
                    (selected (completing-read "Select Playlist: " choices)))
              (when (not (string= "" selected))
                (funcall callback (cadr (assoc selected choices)))))))))))

(defun spotify-track-add ()
  "Adds the track under the cursor on a playlist. Prompts for the playlist."
  (interactive)
  (lexical-let ((selected-track (tabulated-list-get-id)))
    (spotify-select-playlist
     (lambda (playlist)
       (spotify-current-user
        (lambda (user)
          (spotify-api-playlist-add-track
           (spotify-get-item-id user)
           playlist
           (spotify-get-item-uri selected-track)
           (lambda (_)
             (message "Song added.")))))))))


(provide 'spotify-track-search)
