/**
 * YouTube Proxy メインスクリプト
 */

document.addEventListener('DOMContentLoaded', function() {
  // 現在のURLがYouTubeかどうかを確認する関数
  function isYouTubeUrl(url) {
    try {
      const urlObj = new URL(url);
      return urlObj.hostname.includes('youtube.com') || urlObj.hostname.includes('youtu.be');
    } catch (e) {
      return false;
    }
  }

  // YouTube URLから動画IDを抽出する関数
  function extractVideoId(url) {
    try {
      const urlObj = new URL(url);
      let videoId = '';
      
      if (urlObj.hostname.includes('youtube.com')) {
        videoId = urlObj.searchParams.get('v') || '';
      } else if (urlObj.hostname.includes('youtu.be')) {
        videoId = urlObj.pathname.substring(1);
      }
      
      return videoId;
    } catch (e) {
      return '';
    }
  }

  // URL入力フィールドがある場合、IDの自動抽出を設定
  const urlInput = document.getElementById('youtube_url');
  const idInput = document.getElementById('video_id');
  
  if (urlInput && idInput) {
    urlInput.addEventListener('input', function() {
      const url = this.value;
      if (isYouTubeUrl(url)) {
        const videoId = extractVideoId(url);
        if (videoId) {
          idInput.value = videoId;
        }
      }
    });
  }

  // 削除ボタン処理
  const deleteButtons = document.querySelectorAll('.delete-video');
  if (deleteButtons.length > 0) {
    deleteButtons.forEach(button => {
      button.addEventListener('click', function() {
        const videoId = this.getAttribute('data-id');
        if (confirm('この動画をホワイトリストから削除してもよろしいですか？')) {
          fetch(`/delete/${videoId}`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json'
            }
          })
          .then(response => response.json())
          .then(data => {
            if (data.success) {
              const row = document.querySelector(`tr[data-id="${videoId}"]`);
              if (row) {
                row.remove();
              }
              
              // 全て削除された場合のメッセージ表示
              const tbody = document.querySelector('tbody');
              if (tbody && !tbody.hasChildNodes()) {
                const tableResponsive = document.querySelector('.table-responsive');
                if (tableResponsive) {
                  tableResponsive.innerHTML = `
                    <div class="alert alert-info">
                      ホワイトリストに登録された動画はありません。
                    </div>
                  `;
                }
              }
            } else {
              alert('削除中にエラーが発生しました: ' + (data.message || '不明なエラー'));
            }
          })
          .catch(error => {
            console.error('削除エラー:', error);
            alert('削除中にエラーが発生しました');
          });
        }
      });
    });
  }

  // パスワード検証
  const passwordForm = document.querySelector('form[action="/change-password"]');
  if (passwordForm) {
    const newPassword = document.getElementById('new_password');
    const confirmPassword = document.getElementById('confirm_password');
    
    passwordForm.addEventListener('submit', function(e) {
      if (newPassword.value !== confirmPassword.value) {
        e.preventDefault();
        alert('新しいパスワードと確認用パスワードが一致しません。');
      }
      
      if (newPassword.value.length < 8) {
        e.preventDefault();
        alert('パスワードは8文字以上である必要があります。');
      }
    });
  }

  // アラートの自動消去
  const alerts = document.querySelectorAll('.alert:not(.alert-permanent)');
  if (alerts.length > 0) {
    alerts.forEach(alert => {
      setTimeout(() => {
        alert.classList.add('fade-out');
        setTimeout(() => {
          alert.remove();
        }, 500);
      }, 5000);
    });
  }
});
