const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const cookieParser = require('cookie-parser');
const morgan = require('morgan');
const path = require('path');
const fs = require('fs');
const helmet = require('helmet');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcrypt');

// アプリケーション初期化
const app = express();
const port = process.env.PORT || 3000;

// DBの初期化
const dbPath = path.join(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath);

// テーブル作成
db.serialize(() => {
  // ユーザー認証用テーブル
  db.run(`CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);

  // 許可されたYouTube IDのテーブル
  db.run(`CREATE TABLE IF NOT EXISTS whitelist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    video_id TEXT UNIQUE NOT NULL,
    title TEXT,
    requested_by TEXT,
    expires_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )`);

  // 初期管理者ユーザーの追加 (ユーザー名: admin, パスワード: admin123)
  const checkAdmin = db.prepare("SELECT * FROM users WHERE username = ?");
  checkAdmin.get('admin', (err, row) => {
    if (err) {
      console.error('管理者ユーザー確認エラー:', err);
      return;
    }
    
    if (!row) {
      bcrypt.hash('admin123', 10, (err, hash) => {
        if (err) {
          console.error('パスワードハッシュエラー:', err);
          return;
        }
        
        const insertAdmin = db.prepare("INSERT INTO users (username, password) VALUES (?, ?)");
        insertAdmin.run('admin', hash, (err) => {
          if (err) {
            console.error('管理者ユーザー作成エラー:', err);
            return;
          }
          console.log('初期管理者ユーザーが作成されました。ユーザー名: admin, パスワード: admin123');
          console.log('セキュリティのため、ログイン後にパスワードを変更してください！');
        });
        insertAdmin.finalize();
      });
    }
  });
  checkAdmin.finalize();
});

// ミドルウェア設定
app.use(helmet({ contentSecurityPolicy: false }));
app.use(morgan('combined'));
app.use(bodyParser.urlencoded({ extended: false }));
app.use(bodyParser.json());
app.use(cookieParser());
app.use(session({
  secret: 'youtube-proxy-secret-key',
  resave: false,
  saveUninitialized: false,
  cookie: { 
    secure: false,  // 本番環境ではtrueに設定
    maxAge: 24 * 60 * 60 * 1000 // 24時間
  }
}));

// テンプレートエンジン設定
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// 静的ファイル
app.use(express.static(path.join(__dirname, 'public')));

// ホワイトリストの更新
const updateSquidWhitelist = () => {
  return new Promise((resolve, reject) => {
    const whitelistPath = '/var/lib/youtube-proxy/youtube_whitelist.txt';
    
    db.all("SELECT video_id FROM whitelist WHERE expires_at > datetime('now') OR expires_at IS NULL", (err, rows) => {
      if (err) {
        console.error('ホワイトリストDB読み込みエラー:', err);
        reject(err);
        return;
      }
      
      const videoIds = rows.map(row => row.video_id);
      const whitelistContent = videoIds.join('\n');
      
      fs.writeFile(whitelistPath, whitelistContent, (err) => {
        if (err) {
          console.error('ホワイトリストファイル書き込みエラー:', err);
          reject(err);
          return;
        }
        
        // Squidを再読み込み
        const { exec } = require('child_process');
        exec('systemctl reload squid', (err, stdout, stderr) => {
          if (err) {
            console.error('Squid再読み込みエラー:', err);
            reject(err);
            return;
          }
          console.log('ホワイトリストとSquidを更新しました');
          resolve();
        });
      });
    });
  });
};

// 認証確認ミドルウェア
const isAuthenticated = (req, res, next) => {
  if (req.session.user) {
    return next();
  }
  res.redirect('/login');
};

// ルート
app.get('/', (req, res) => {
  res.redirect('/dashboard');
});

// ログインページ
app.get('/login', (req, res) => {
  res.render('login', { error: null });
});

// ログイン処理
app.post('/login', (req, res) => {
  const { username, password } = req.body;
  
  db.get("SELECT * FROM users WHERE username = ?", [username], (err, user) => {
    if (err || !user) {
      return res.render('login', { error: 'ユーザー名またはパスワードが間違っています' });
    }
    
    bcrypt.compare(password, user.password, (err, result) => {
      if (err || !result) {
        return res.render('login', { error: 'ユーザー名またはパスワードが間違っています' });
      }
      
      req.session.user = { id: user.id, username: user.username };
      res.redirect('/dashboard');
    });
  });
});

// ダッシュボード
app.get('/dashboard', isAuthenticated, (req, res) => {
  db.all("SELECT * FROM whitelist ORDER BY created_at DESC", (err, videos) => {
    if (err) {
      console.error('ホワイトリスト取得エラー:', err);
      return res.status(500).send('サーバーエラー');
    }
    
    res.render('dashboard', { user: req.session.user, videos: videos });
  });
});

// 動画申請ページ
app.get('/request', (req, res) => {
  const youtubeUrl = req.query.url || '';
  let videoId = '';
  
  // YouTube URLからvideo_idを抽出
  if (youtubeUrl) {
    const urlObj = new URL(youtubeUrl);
    if (urlObj.hostname.includes('youtube.com')) {
      videoId = urlObj.searchParams.get('v') || '';
    } else if (urlObj.hostname.includes('youtu.be')) {
      videoId = urlObj.pathname.substring(1);
    }
  }
  
  res.render('request', { youtubeUrl, videoId, message: null });
});

// 動画申請処理
app.post('/request', (req, res) => {
  const { video_id, title } = req.body;
  
  if (!video_id) {
    return res.render('request', { 
      youtubeUrl: req.body.youtube_url || '',
      videoId: '',
      message: { type: 'error', text: '動画IDが必要です' }
    });
  }
  
  // 有効期限を1日後に設定
  const expires = new Date();
  expires.setDate(expires.getDate() + 1);
  
  db.run("INSERT OR REPLACE INTO whitelist (video_id, title, requested_by, expires_at) VALUES (?, ?, ?, ?)",
    [video_id, title || '無題', 'guest', expires.toISOString()],
    async function(err) {
      if (err) {
        console.error('ホワイトリスト追加エラー:', err);
        return res.render('request', { 
          youtubeUrl: req.body.youtube_url || '',
          videoId: video_id,
          message: { type: 'error', text: 'データベースエラー' }
        });
      }
      
      try {
        await updateSquidWhitelist();
        return res.render('request', { 
          youtubeUrl: req.body.youtube_url || '',
          videoId: video_id,
          message: { 
            type: 'success', 
            text: '動画が承認されました。YouTube URLに再度アクセスしてください。24時間後に期限切れになります。' 
          }
        });
      } catch (err) {
        console.error('ホワイトリスト更新エラー:', err);
        return res.render('request', { 
          youtubeUrl: req.body.youtube_url || '',
          videoId: video_id,
          message: { type: 'error', text: 'ホワイトリスト更新エラー' }
        });
      }
    }
  );
});

// 動画削除
app.post('/delete/:id', isAuthenticated, (req, res) => {
  const videoId = req.params.id;
  
  db.run("DELETE FROM whitelist WHERE video_id = ?", [videoId], async function(err) {
    if (err) {
      console.error('動画削除エラー:', err);
      return res.status(500).json({ success: false, message: 'データベースエラー' });
    }
    
    try {
      await updateSquidWhitelist();
      return res.json({ success: true });
    } catch (err) {
      console.error('ホワイトリスト更新エラー:', err);
      return res.status(500).json({ success: false, message: 'ホワイトリスト更新エラー' });
    }
  });
});

// パスワード変更
app.get('/change-password', isAuthenticated, (req, res) => {
  res.render('change-password', { user: req.session.user, message: null });
});

app.post('/change-password', isAuthenticated, (req, res) => {
  const { current_password, new_password, confirm_password } = req.body;
  
  if (new_password !== confirm_password) {
    return res.render('change-password', { 
      user: req.session.user, 
      message: { type: 'error', text: '新しいパスワードと確認用パスワードが一致しません' }
    });
  }
  
  db.get("SELECT * FROM users WHERE id = ?", [req.session.user.id], (err, user) => {
    if (err || !user) {
      return res.render('change-password', { 
        user: req.session.user, 
        message: { type: 'error', text: 'ユーザーが見つかりません' }
      });
    }
    
    bcrypt.compare(current_password, user.password, (err, result) => {
      if (err || !result) {
        return res.render('change-password', { 
          user: req.session.user, 
          message: { type: 'error', text: '現在のパスワードが間違っています' }
        });
      }
      
      bcrypt.hash(new_password, 10, (err, hash) => {
        if (err) {
          return res.render('change-password', { 
            user: req.session.user, 
            message: { type: 'error', text: 'パスワードハッシュエラー' }
          });
        }
        
        db.run("UPDATE users SET password = ? WHERE id = ?", [hash, req.session.user.id], (err) => {
          if (err) {
            return res.render('change-password', { 
              user: req.session.user, 
              message: { type: 'error', text: 'パスワード更新エラー' }
            });
          }
          
          return res.render('change-password', { 
            user: req.session.user, 
            message: { type: 'success', text: 'パスワードが更新されました' }
          });
        });
      });
    });
  });
});

// ログアウト
app.get('/logout', (req, res) => {
  req.session.destroy();
  res.redirect('/login');
});

// ブロックページ
app.get('/blocked', (req, res) => {
  const youtubeUrl = req.query.url || '';
  res.render('blocked', { youtubeUrl });
});

// YouTubeブロックAPI（Squidリダイレクト用）
app.get('/api/youtube-blocked', (req, res) => {
  const youtubeUrl = req.query.url || '';
  res.redirect(`/blocked?url=${encodeURIComponent(youtubeUrl)}`);
});

// サーバー起動
app.listen(port, () => {
  console.log(`YouTube Proxy Webアプリを開始しました: http://localhost:${port}`);
  
  // 最初にホワイトリスト更新
  updateSquidWhitelist()
    .then(() => console.log('初期ホワイトリストを更新しました'))
    .catch(err => console.error('初期ホワイトリスト更新エラー:', err));
});
