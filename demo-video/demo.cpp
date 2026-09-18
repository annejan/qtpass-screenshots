// SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
// SPDX-License-Identifier: GPL-3.0-or-later
// Demo recorder: drives real QtPass widgets under the offscreen platform,
// grabs every top-level window a dozen times a second, composites them with
// a drawn cursor and writes numbered PNG frames for ffmpeg.
//
// usage: demo <clip> <outdir>   clips: wizard | addpassword | menubar | profiles
#include "configdialog.h"
#include "firstrunwizard.h"
#include "mainwindow.h"
#include "passworddialog.h"
#include "profile.h"
#include "qtpasssettings.h"
#include <QAction>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QDir>
#include <QFile>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QPainter>
#include <QPainterPath>
#include <QPushButton>
#include <QSettings>
#include <QStandardPaths>
#include <QTabWidget>
#include <QTemporaryDir>
#include <QTimer>
#include <QToolButton>
#include <QTreeView>
#include <QWizard>
#include <functional>

namespace {

struct Recorder {
  QString outDir;
  int frame = 0;
  QPointF cursor{-100, -100};
  QPointF cursorTarget{-100, -100};
  QSize canvas{960, 640};
  QColor background{0x2b, 0x2e, 0x36};
  bool clicking = false;

  void grab() {
    QImage img(canvas, QImage::Format_ARGB32);
    img.fill(background);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    // Bottom-most first: the main window, then dialogs, then popups.
    QList<QWidget *> tops = QApplication::topLevelWidgets();
    std::stable_sort(tops.begin(), tops.end(), [](QWidget *a, QWidget *b) {
      auto rank = [](QWidget *w) {
        if (w->windowType() == Qt::Popup) return 3;
        if (w->windowType() == Qt::ToolTip) return 4;
        if (w->isModal() || qobject_cast<QDialog *>(w)) return 2;
        return 1;
      };
      return rank(a) < rank(b);
    });
    for (QWidget *w : tops) {
      if (!w->isVisible() || w->windowType() == Qt::Desktop)
        continue;
      const QPixmap pm = w->grab();
      const QPoint pos = w->geometry().topLeft();
      // Soft shadow for windows above the main one.
      if (qobject_cast<QDialog *>(w) || w->windowType() == Qt::Popup) {
        p.setPen(Qt::NoPen);
        for (int i = 8; i > 0; --i) {
          p.setBrush(QColor(0, 0, 0, 10));
          p.drawRoundedRect(QRectF(pos.x() - i, pos.y() - i + 3,
                                   pm.width() + 2 * i, pm.height() + 2 * i),
                            6, 6);
        }
      }
      p.drawPixmap(pos, pm);
    }
    // Cursor eases towards its target.
    cursor += (cursorTarget - cursor) * 0.35;
    QPainterPath arrow;
    arrow.moveTo(0, 0);
    arrow.lineTo(0, 17);
    arrow.lineTo(4.5, 13);
    arrow.lineTo(7.5, 19.5);
    arrow.lineTo(10, 18.5);
    arrow.lineTo(7, 12);
    arrow.lineTo(12.5, 12);
    arrow.closeSubpath();
    p.translate(cursor);
    if (clicking) {
      p.setPen(Qt::NoPen);
      p.setBrush(QColor(255, 200, 0, 90));
      p.drawEllipse(QPointF(1, 1), 14, 14);
    }
    p.setPen(QPen(Qt::white, 1.5));
    p.setBrush(Qt::black);
    p.drawPath(arrow);
    p.end();
    img.save(QStringLiteral("%1/frame%2.png").arg(outDir).arg(frame++, 5, 10, QLatin1Char('0')));
  }
};

/// A scripted sequence: (delay in frames, action).
struct Script {
  QList<QPair<int, std::function<void()>>> steps;
  Recorder *rec;
  QTimer timer;
  int idx = 0;
  int wait = 0;
  std::function<void()> done;

  void add(int frames, std::function<void()> fn) { steps.append({frames, std::move(fn)}); }
  void pause(int frames) { add(frames, [] {}); }
  void start() {
    timer.setInterval(1000 / 12);
    QObject::connect(&timer, &QTimer::timeout, [this]() {
      rec->grab();
      if (wait > 0) {
        --wait;
        return;
      }
      if (idx >= steps.size()) {
        timer.stop();
        done();
        return;
      }
      wait = steps[idx].first;
      steps[idx].second();
      ++idx;
    });
    timer.start();
  }
};

auto centerOf(QWidget *w) -> QPointF {
  return QPointF(w->mapToGlobal(w->rect().center()));
}

void moveTo(Recorder &r, QWidget *w) { r.cursorTarget = centerOf(w); }

void click(Script &s, QWidget *w) {
  s.add(4, [&s, w]() { s.rec->cursorTarget = centerOf(w); });
  s.add(2, [&s, w]() {
    s.rec->cursor = centerOf(w);
    s.rec->clicking = true;
    if (auto *b = qobject_cast<QAbstractButton *>(w)) b->click();
  });
  s.add(0, [&s]() { s.rec->clicking = false; });
}

void type(Script &s, QLineEdit *edit, const QString &text, int perChar = 1) {
  s.add(2, [&s, edit]() {
    s.rec->cursorTarget = centerOf(edit);
    edit->setFocus();
    edit->clear();
  });
  for (int i = 0; i < text.size(); ++i) {
    s.add(perChar, [edit, ch = text.at(i)]() {
      edit->insert(QString(ch));
      emit edit->textEdited(edit->text());
    });
  }
}

void setupSettings(QTemporaryDir &dir, const QString &gpg, const QString &store) {
  QStandardPaths::setTestModeEnabled(true);
  QSettings::setDefaultFormat(QSettings::IniFormat);
  QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, dir.filePath("cfg"));
  AppSettings s = QtPassSettings::load();
  s.gpgExecutable = gpg;
  s.gitExecutable = QString();
  s.passExecutable = QString();
  s.useGit = false;
  s.usePass = false;
  s.passStore = store;
  s.useTemplate = true;
  s.passTemplate = QStringLiteral("login\nurl\nOTP");
  s.hidePassword = true;
  s.useTrayIcon = false;
  QtPassSettings::save(s);
  Profiles profiles;
  Profile home;
  home.path = store;
  profiles.insert(QStringLiteral("Home"), home);
  Profile work;
  work.path = QFileInfo(store).path() + QStringLiteral("/work-passwords");
  work.useGit = true;
  work.autoPull = true;
  profiles.insert(QStringLiteral("Work"), work);
  QtPassSettings::setProfiles(profiles);
  s = QtPassSettings::load();
  s.activeProfile = QStringLiteral("Home");
  QtPassSettings::save(s);
}

auto writeGpgStandIn(const QString &path) -> QString {
  QFile f(path);
  f.open(QIODevice::WriteOnly);
  f.write("#!/bin/sh\n"
          "out=\"\"; prev=\"\"\n"
          "for a in \"$@\"; do [ \"$prev\" = \"--output\" ] && out=\"$a\"; prev=\"$a\"; done\n"
          "case \"$*\" in\n"
          "*--list-secret-keys*) printf '%s\\n' "
          "'sec:u:255:22:31850CF72D9CDDE9:1774947438:::u:::escarESCA:::+:::23::0:' "
          "'fpr:::::::::13A47CCE2B3DA3AC340A274A31850CF72D9CDDE9:' "
          "'uid:u::::1774947438::CBF2::Anne Jan Brouwer <annejan@example.org>::::::::::0:' "
          "'sec:u:4096:1:6DF67C6BAD8383CB:1700000000:::u:::escarESCA:::+:::23::0:' "
          "'fpr:::::::::4EF2550F79F4E9E68B09F71D693A0AF3FA364E76:' "
          "'uid:u::::1700000000::CBF3::Hackerspace shared key <keys@example.org>::::::::::0:';;\n"
          "esac\n"
          "[ -n \"$out\" ] && : > \"$out\"\n"
          "exit 0\n");
  f.close();
  QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
  return path;
}

void makeStore(const QString &store) {
  QDir().mkpath(store);
  for (const char *rel : {"github.com.gpg", "hackerspace/wifi.gpg", "hackerspace/door.gpg",
                          "personal/banking/ing.gpg", "personal/mastodon.gpg",
                          "work/vpn.gpg", "work/gitlab.gpg"}) {
    QFileInfo fi(QDir(store).filePath(rel));
    QDir().mkpath(fi.path());
    QFile f(fi.filePath());
    f.open(QIODevice::WriteOnly);
    f.write("x");
  }
  QFile id(QDir(store).filePath(".gpg-id"));
  id.open(QIODevice::WriteOnly);
  id.write("13A47CCE2B3DA3AC340A274A31850CF72D9CDDE9\n");
}

} // namespace

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  const QString clip = argc > 1 ? argv[1] : "menubar";
  Recorder rec;
  rec.outDir = argc > 2 ? argv[2] : ".";
  QDir().mkpath(rec.outDir);
  // A fixed, readable location: paths show up in the frames.
  const QString base = QStringLiteral("/tmp/qtpass-demo");
  QDir(base).removeRecursively();
  QDir().mkpath(base + "/bin");
  qputenv("PATH", (base + "/bin").toUtf8());
  qputenv("HOME", base.toUtf8());
  static QTemporaryDir dir(base + "/run-XXXXXX");
  const QString gpg = writeGpgStandIn(base + "/bin/gpg");
  const QString store = base + "/password-store";
  Script script;
  script.rec = &rec;
  script.done = [&]() { app.quit(); };

  if (clip == "wizard") {
    setupSettings(dir, gpg, base + "/password-store");
    auto *w = new FirstRunWizard;
    w->resize(700, 470);
    w->move(130, 85);
    w->show();
    auto next = [w]() -> QAbstractButton * { return w->button(QWizard::NextButton); };
    script.pause(14);
    click(script, next());
    script.pause(16);
    click(script, next());
    script.pause(6);
    script.add(10, [w]() {
      auto *list = w->currentPage()->findChild<QListWidget *>();
      list->item(1)->setCheckState(Qt::Unchecked); // only my own key
    });
    click(script, next());
    script.pause(4);
    script.add(0, [w, &rec]() {
      rec.cursorTarget = centerOf(w->currentPage()->findChildren<QLineEdit *>().first());
    });
    script.add(0, [w, base]() {
      auto *edit = w->currentPage()->findChildren<QLineEdit *>().first();
      edit->setText(base + QStringLiteral("/password-store"));
      emit edit->textEdited(edit->text());
    });
    script.pause(14);
    click(script, next());
    script.pause(20);
    click(script, w->button(QWizard::FinishButton));
    script.pause(4);
  } else {
    makeStore(store);
    setupSettings(dir, gpg, store);
    auto *mw = new MainWindow;
    mw->resize(860, 560);
    mw->move(50, 40);
    mw->show();
    auto *tree = mw->findChild<QTreeView *>(QStringLiteral("treeView"));
    // QFileSystemModel fills in asynchronously; expand once it has.
    script.add(6, [tree]() { tree->expandAll(); });
    script.add(2, [tree]() { tree->expandAll(); });
    if (clip == "menubar") {
      QMenuBar *bar = mw->menuBar();
      QList<QAction *> menus = bar->actions();
      script.pause(10);
      for (int i = 0; i < menus.size(); ++i) {
        script.add(3, [&rec, bar, menus, i]() {
          rec.cursorTarget = QPointF(bar->mapToGlobal(bar->actionGeometry(menus[i]).center()));
        });
        script.add(14, [bar, menus, i]() { bar->setActiveAction(menus[i]); });
      }
      script.add(4, [bar]() { bar->setActiveAction(nullptr); if (auto *m = qobject_cast<QMenu *>(QApplication::activePopupWidget())) m->hide(); });
      script.add(6, [&rec, tree]() { rec.cursorTarget = centerOf(tree); });
      script.add(16, [mw]() { mw->findChild<QAction *>(QStringLiteral("actionShowMenuBar"))->trigger(); });
      script.add(16, [mw]() { mw->findChild<QAction *>(QStringLiteral("actionShowMenuBar"))->trigger(); });
      script.pause(6);
    } else if (clip == "addpassword") {
      script.pause(8);
      script.add(6, [&rec, tree, mw]() {
        // select the work folder
        QModelIndex idx;
        for (int r = 0; r < tree->model()->rowCount(tree->rootIndex()); ++r) {
          QModelIndex c = tree->model()->index(r, 0, tree->rootIndex());
          if (c.data().toString().startsWith("work")) idx = c;
        }
        tree->setCurrentIndex(idx);
        rec.cursorTarget = QPointF(tree->viewport()->mapToGlobal(tree->visualRect(idx).center()));
      });
      auto *add = mw->findChild<QAction *>(QStringLiteral("actionAddPassword"));
      script.add(2, [&rec, mw, add]() {
        for (QToolButton *b : mw->findChildren<QToolButton *>())
          if (b->defaultAction() == add) rec.cursorTarget = centerOf(b);
      });
      script.add(2, [&rec]() { rec.clicking = true; });
      script.add(0, [&rec, add]() {
        rec.clicking = false;
        QTimer::singleShot(0, [add]() { add->trigger(); }); // modal exec inside
      });
      script.pause(8);
      script.add(0, [&rec]() {
        auto *d = qobject_cast<PasswordDialog *>(QApplication::activeModalWidget());
        if (d) { d->move(230, 120); }
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QLineEdit *>("nameEdit"));
      });
      for (QChar ch : QStringLiteral("gitlab.example.org")) {
        script.add(1, [ch]() {
          auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
          auto *e = d->findChild<QLineEdit *>("nameEdit");
          e->insert(QString(ch));
        });
      }
      script.pause(6);
      script.add(4, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *b = d->findChild<QToolButton *>("createPasswordButton");
        rec.cursorTarget = centerOf(b);
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        rec.clicking = true;
        d->findChild<QToolButton *>("createPasswordButton")->click();
      });
      script.add(6, [&rec]() {
        rec.clicking = false;
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        d->findChild<QCheckBox *>("checkBoxShow")->click();
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        if (auto *e = d->findChild<QLineEdit *>("login")) { rec.cursorTarget = centerOf(e); e->setFocus(); }
      });
      for (QChar ch : QStringLiteral("annejan")) {
        script.add(1, [ch]() {
          auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
          if (auto *e = d->findChild<QLineEdit *>("login")) e->insert(QString(ch));
        });
      }
      script.pause(8);
      script.add(4, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QDialogButtonBox *>()->button(QDialogButtonBox::Ok));
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        rec.clicking = true;
        d->findChild<QDialogButtonBox *>()->button(QDialogButtonBox::Ok)->click();
      });
      script.add(6, [&rec, tree]() { rec.clicking = false; tree->expandAll(); });
      script.pause(14);
    } else if (clip == "profiles") {
      script.pause(8);
      auto *cfg = mw->findChild<QAction *>(QStringLiteral("actionConfig"));
      script.add(2, [&rec, mw, cfg]() {
        for (QToolButton *b : mw->findChildren<QToolButton *>())
          if (b->defaultAction() == cfg) rec.cursorTarget = centerOf(b);
      });
      script.add(2, [&rec]() { rec.clicking = true; });
      script.add(0, [&rec, cfg]() { rec.clicking = false; QTimer::singleShot(0, [cfg]() { cfg->trigger(); }); });
      script.pause(8);
      script.add(2, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        d->resize(700, 500);
        d->move(130, 70);
        auto *tabs = d->findChild<QTabWidget *>();
        rec.cursorTarget = QPointF(tabs->tabBar()->mapToGlobal(tabs->tabBar()->tabRect(2).center()));
      });
      script.add(10, []() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        d->findChild<QTabWidget *>()->setCurrentIndex(2);
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QToolButton *>("addButton"));
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.clicking = true;
        d->findChild<QToolButton *>("addButton")->click();
      });
      script.add(4, [&rec]() {
        rec.clicking = false;
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QLineEdit *>("profileName"));
        d->findChild<QLineEdit *>("profileName")->clear();
      });
      for (QChar ch : QStringLiteral("Hackerspace")) {
        script.add(1, [ch]() {
          auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
          auto *e = d->findChild<QLineEdit *>("profileName");
          e->insert(QString(ch));
          emit e->textEdited(e->text());
        });
      }
      script.add(4, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QLineEdit *>("profilePath"));
        d->findChild<QLineEdit *>("profilePath")->clear();
      });
      for (QChar ch : QStringLiteral("/tmp/qtpass-demo/hackerspace-passwords")) {
        script.add(0, [ch]() {
          auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
          auto *e = d->findChild<QLineEdit *>("profilePath");
          e->insert(QString(ch));
          emit e->textEdited(e->text());
        });
      }
      script.pause(8);
      for (int row : {1, 0, 2}) {
        script.add(3, [&rec, row]() {
          auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
          auto *list = d->findChild<QListWidget *>("profileList");
          rec.cursorTarget = QPointF(list->viewport()->mapToGlobal(list->visualItemRect(list->item(row)).center()));
        });
        script.add(12, [row]() {
          auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
          d->findChild<QListWidget *>("profileList")->setCurrentRow(row);
        });
      }
      script.add(2, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.cursorTarget = centerOf(d->findChild<QDialogButtonBox *>()->button(QDialogButtonBox::Cancel));
      });
      script.add(2, [&rec]() {
        auto *d = qobject_cast<ConfigDialog *>(QApplication::activeModalWidget());
        rec.clicking = true;
        d->reject();
      });
      script.add(8, [&rec]() { rec.clicking = false; });
    }
  }
  script.start();
  return app.exec();
}
