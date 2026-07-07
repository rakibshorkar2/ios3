

> Add **Magnet Link Download** support to the existing **Downloads** tab of my Flutter iOS app. Do not modify the existing HTTP download functionality—integrate this as an additional download type.
>
> Requirements:
>
> * Extend the existing **New Download** dialog to accept both:
>
>   * HTTP/HTTPS direct download links
>   * Magnet links (`magnet:?xt=urn:btih:...`)
> * Automatically detect whether the pasted input is an HTTP URL or a magnet link.
> * If it is a magnet link:
>
>   * Parse the magnet URI.
>   * Extract and display:
>
>     * Torrent name (if available)
>     * Info hash
>     * Trackers
>   * Start fetching torrent metadata.
>   * Show a loading indicator while metadata is being retrieved.
> * After metadata is received, display a confirmation dialog showing:
>
>   * Torrent name
>   * Total size
>   * Number of files
>   * File list
> * Allow the user to:
>
>   * Download all files
>   * Select individual files to download
>   * Choose the save location
> * Add the torrent to the app's existing download queue and display its progress in the Downloads tab using the current download card UI.
> * Support:
>
>   * Pause
>   * Resume
>   * Cancel
>   * Progress
>   * Download speed
>   * Upload speed
>   * ETA
>   * Seeders and peers
> * When the torrent finishes downloading, save the files to the selected location and mark the task as completed.
> * Continue to use the app's existing SOCKS5 proxy if it is enabled.
> * Handle invalid magnet links and metadata retrieval failures gracefully.
> * Keep the implementation modular by introducing a `TorrentDownloadService` (or equivalent) that integrates with the existing download manager instead of duplicating UI or download logic.
> * Preserve the current UI design, architecture, and state management. The user should be able to manage HTTP downloads and torrent downloads from the same Downloads tab with a consistent experience.
