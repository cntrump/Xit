import Cocoa

protocol RepositoryController: class
{
  var selectedModel: FileChangesModel? { get set }
  
  func select(sha: String)
}

/// XTDocument's main window controller.
class XTWindowController: NSWindowController, NSWindowDelegate,
                          RepositoryController
{
  @IBOutlet var sidebarController: XTSidebarController!
  @IBOutlet weak var mainSplitView: NSSplitView!
  
  var historyController: XTHistoryViewController!
  weak var xtDocument: XTDocument?
  var titleBarController: TitleBarViewController?
  var refsChangedObserver: NSObjectProtocol?
  var selectedModel: FileChangesModel?
  {
    didSet
    {
      guard selectedModel.map({ (s) in oldValue.map { (o) in s != o }
          ?? true }) ?? (oldValue != nil)
      else { return }
      var userInfo = [AnyHashable: Any]()
      
      userInfo[NSKeyValueChangeKey.newKey] = selectedModel
      userInfo[NSKeyValueChangeKey.oldKey] = oldValue
      
      NotificationCenter.default.post(
          name: NSNotification.Name.XTSelectedModelChanged,
          object: self,
          userInfo: userInfo)
      
      if #available(OSX 10.12.2, *) {
        touchBar = makeTouchBar()
      }
      
      if !navigating {
        navForwardStack.removeAll()
        oldValue.map { navBackStack.append($0) }
      }
      updateNavButtons()
    }
  }
  var navBackStack = [FileChangesModel]()
  var navForwardStack = [FileChangesModel]()
  var navigating = false
  var sidebarHidden: Bool
  {
    return mainSplitView.isSubviewCollapsed(mainSplitView.subviews[0])
  }
  var savedSidebarWidth: CGFloat = 180
  
  var currentOperation: XTOperationController?
  
  override var document: AnyObject?
  {
    didSet
    {
      xtDocument = document as! XTDocument?
    }
  }
  
  override func windowDidLoad()
  {
    super.windowDidLoad()
    
    let window = self.window!
    
    window.titleVisibility = .hidden
    window.delegate = self
    historyController = XTHistoryViewController()
    mainSplitView.addArrangedSubview(historyController.view)
    mainSplitView.removeArrangedSubview(mainSplitView.arrangedSubviews[1])
    window.makeFirstResponder(historyController.historyTable)
    
    let repo = xtDocument!.repository!
    
    refsChangedObserver = NotificationCenter.default.addObserver(
        forName: NSNotification.Name.XTRepositoryRefsChanged,
        object: repo, queue: nil) {
      [weak self] _ in
      self?.updateBranchList()
    }
    window.addObserver(self, forKeyPath: #keyPath(NSWindow.title),
                       options: [], context: nil)
    repo.addObserver(self, forKeyPath: #keyPath(XTRepository.currentBranch),
                     options: [], context: nil)
    sidebarController.repo = repo
    historyController.windowDidLoad()
    historyController.repo = repo
    updateMiniwindowTitle()
    updateNavButtons()
  }
  
  deinit
  {
    let center = NotificationCenter.default
    
    refsChangedObserver.map { center.removeObserver($0) }
    center.removeObserver(self)
    currentOperation?.canceled = true
    window?.removeObserver(self, forKeyPath: #keyPath(NSWindow.title))
  }
  
  override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?)
  {
    switch object {
      case let repo as XTRepository:
        if keyPath == #keyPath(XTRepository.currentBranch) {
          titleBarController?.selectedBranch = repo.currentBranch
          updateMiniwindowTitle()
        }
      case _ as NSWindow:
        if keyPath == #keyPath(NSWindow.title) {
          updateMiniwindowTitle()
        }
      default:
        break
    }
  }
  
  func select(sha: String)
  {
    guard let commit = XTCommit(sha: sha, repository: xtDocument!.repository)
    else { return }
  
    selectedModel = CommitChanges(repository: xtDocument!.repository,
                                  commit: commit)
  }
  
  func select(oid: GitOID)
  {
    guard let commit = XTCommit(oid: oid, repository: xtDocument!.repository)
    else { return }
  
    selectedModel = CommitChanges(repository: xtDocument!.repository,
                                  commit: commit)
  }
  
  func updateNavButtons()
  {
    updateNavControl(titleBarController?.navButtons)

    if #available(OSX 10.12.2, *),
       let item = self.touchBar?.item(forIdentifier:
                                      NSTouchBarItemIdentifier.navigation) {
      updateNavControl(item.view as? NSSegmentedControl)
    }
  }
  
  func updateNavControl(_ control: NSSegmentedControl?)
  {
    guard let control = control
    else { return }
    
    control.setEnabled(!navBackStack.isEmpty, forSegment: 0)
    control.setEnabled(!navForwardStack.isEmpty, forSegment: 1)
  }
  
  func updateMiniwindowTitle()
  {
    guard let window = self.window,
          let repo = xtDocument?.repository
    else { return }
  
    if let currentBranch = repo.currentBranch {
      window.miniwindowTitle = "\(window.title) - \(currentBranch)"
    }
    else {
      window.miniwindowTitle = window.title
    }
  }
  
  func updateBranchList()
  {
    guard let repo = xtDocument?.repository
    else { return }
    
    self.titleBarController?.updateBranchList(
        repo.localBranches().flatMap { $0.shortName },
        current: repo.currentBranch)
  }
  
  public func startRenameBranch(_ branchName: String)
  {
    _ = startOperation { XTRenameBranchController(windowController: self,
                                                    branchName: branchName) }
  }
  
  /// Returns the new operation, if any, mostly because the generic type must
  /// be part of the signature.
  func startOperation<OperationType: XTSimpleOperationController>()
      -> OperationType?
  {
    return startOperation { return OperationType(windowController: self) }
           as? OperationType
  }
  
  func startOperation(factory: () -> XTOperationController)
      -> XTOperationController?
  {
    if let operation = currentOperation {
      NSLog("Can't start new operation, already have \(operation)")
      return nil
    }
    else {
      let operation = factory()
      
      operation.start()
      currentOperation = operation
      return operation
    }
  }
  
  /// Called by the operation controller when it's done.
  func operationEnded(_ operation: XTOperationController)
  {
    if currentOperation == operation {
      currentOperation = nil
    }
  }
  
  func updateRemotesMenu(_ menu: NSMenu)
  {
    let remoteNames = xtDocument!.repository.remoteNames()
    
    menu.removeAllItems()
    for name in remoteNames {
      menu.addItem(NSMenuItem(title: name,
                              action: #selector(self.remoteSettings(_:)),
                              keyEquivalent: ""))
    }
  }
  
  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
  {
    guard let action = menuItem.action
    else { return false }
    var result = false
    
    switch action {

      case #selector(self.goBack(_:)):
        result = !navBackStack.isEmpty
      
      case #selector(self.goForward(_:)):
        result = !navForwardStack.isEmpty

      case #selector(self.refresh(_:)):
        result = !xtDocument!.repository.isWriting

      case #selector(self.showHideSidebar(_:)):
        result = true
        if sidebarHidden {
          menuItem.title = NSLocalizedString("Show Sidebar", comment: "")
        }
        else {
          menuItem.title = NSLocalizedString("Hide Sidebar", comment: "")
        }

      case #selector(self.verticalLayout(_:)):
        result = true
        menuItem.state = historyController.mainSplitView.isVertical
            ? NSOnState : NSOffState

      case #selector(self.horizontalLayout(_:)):
        result = true
        menuItem.state = historyController.mainSplitView.isVertical
            ? NSOffState : NSOnState

      case #selector(self.remoteSettings(_:)):
        result = true
      
      case #selector(self.newTag(_:)):
        result = true

      default:
        result = false
    }
    return result
  }
  
  func windowWillClose(_ notification: Notification)
  {
    titleBarController?.titleLabel.unbind("value")
    titleBarController?.proxyIcon.unbind("hidden")
    titleBarController?.spinner.unbind("hidden")
    xtDocument?.repository.removeObserver(
        self, forKeyPath: #keyPath(XTRepository.currentBranch))
    // For some reason this avoids a crash
    window?.makeFirstResponder(nil)
  }
}

// MARK: NSSplitViewDelegate
extension XTWindowController: NSSplitViewDelegate
{
  func splitView(_ splitView: NSSplitView,
                 shouldAdjustSizeOfSubview view: NSView) -> Bool
  {
    if (splitView == mainSplitView) &&
       (view == mainSplitView.arrangedSubviews[0]) {
      return false
    }
    return true
  }
}

// MARK: XTTitleBarDelegate
extension XTWindowController: TitleBarDelegate
{
  func branchSelecetd(_ branch: String)
  {
    try? xtDocument!.repository!.checkout(branch: branch)
  }
  
  var viewStates: (sidebar: Bool, history: Bool, details: Bool)
  {
    return (!sidebarHidden,
            !historyController.historyHidden,
            !historyController.detailsHidden)
  }
  
  func goBack() { goBack(self) }
  func goForward() { goForward(self) }
  func fetchSelected() { fetch(self) }
  func pushSelected() { push(self) }
  func pullSelected() { pull(self) }
  func showHideSidebar() { showHideSidebar(self) }
  func showHideHistory() { showHideHistory(self) }
  func showHideDetails() { showHideDetails(self) }
}

// MARK: NSToolbarDelegate
extension XTWindowController: NSToolbarDelegate
{
  func toolbarWillAddItem(_ notification: Notification)
  {
    guard let item = notification.userInfo?["item"] as? NSToolbarItem,
          item.itemIdentifier == "com.uncommonplace.xit.titlebar",
          let viewController = TitleBarViewController(nibName: "TitleBar",
                                                      bundle: nil)
    else { return }
    
    let repository = xtDocument!.repository!
    let inverseBindingOptions =
        [NSValueTransformerNameBindingOption:
         NSValueTransformerName.negateBooleanTransformerName]

    titleBarController = viewController
    item.view = viewController.view

    viewController.delegate = self
    viewController.titleLabel.bind("value",
                                   to: window! as NSWindow,
                                   withKeyPath: #keyPath(NSWindow.title),
                                   options: nil)
    viewController.proxyIcon.bind("hidden",
                                  to: repository.queue,
                                  withKeyPath: #keyPath(TaskQueue.busy),
                                  options: nil)
    viewController.bind(#keyPath(TitleBarViewController.progressHidden),
                        to: repository.queue,
                        withKeyPath: #keyPath(TaskQueue.busy),
                        options: inverseBindingOptions)
    viewController.spinner.startAnimation(nil)
    updateBranchList()
    viewController.selectedBranch = repository.currentBranch
    viewController.observe(repository: repository)
  }
}

// MARK: NSTouchBar
fileprivate extension NSTouchBarItemIdentifier
{
  static let
      navigation = NSTouchBarItemIdentifier("com.uncommonplace.xit.nav"),
      staging = NSTouchBarItemIdentifier("com.uncommonplace.xit.staging"),
      unstageAll = NSTouchBarItemIdentifier("com.uncommonplace.xit.unstageall"),
      stageAll = NSTouchBarItemIdentifier("com.uncommonplace.xit.stageall")
}

@available(OSX 10.12.2, *)
extension XTWindowController: NSTouchBarDelegate
{
  override func makeTouchBar() -> NSTouchBar?
  {
    let bar = NSTouchBar()
    
    bar.delegate = self
    if selectedModel is StagingChanges {
      bar.defaultItemIdentifiers = [ .navigation, .unstageAll, .stageAll ]
    }
    else {
      bar.defaultItemIdentifiers = [ .navigation, .staging ]
    }
    
    return bar
  }
  
  func touchBarButton(identifier: NSTouchBarItemIdentifier,
                      title: String, image: NSImage?,
                      target: Any, action: Selector) -> NSCustomTouchBarItem
  {
    let item = NSCustomTouchBarItem(identifier: identifier)
    
    if let image = image {
      item.view = NSButton(title: title, image: image,
                           target: target, action: action)
    }
    else {
      item.view = NSButton(title: title, target: target, action: action)
    }
    return item
  }
  
  func touchBar(_ touchBar: NSTouchBar,
                makeItemForIdentifier identifier: NSTouchBarItemIdentifier)
                -> NSTouchBarItem?
  {
    switch identifier {

      case NSTouchBarItemIdentifier.navigation:
        let control = NSSegmentedControl(
                images: [NSImage(named: NSImageNameGoBackTemplate)!,
                         NSImage(named: NSImageNameGoForwardTemplate)!],
                trackingMode: .momentary,
                target: titleBarController,
                action: #selector(TitleBarViewController.navigate(_:)))
        let item = NSCustomTouchBarItem(identifier: identifier)
      
        control.segmentStyle = .separated
        item.view = control
        return item

      case NSTouchBarItemIdentifier.staging:
        guard let stagingImage = NSImage(named: "stagingTemplate")
        else { return nil }
      
        return touchBarButton(
            identifier: identifier, title: "Staging", image: stagingImage,
            target: self, action: #selector(XTWindowController.showStaging(_:)))

      case NSTouchBarItemIdentifier.unstageAll:
        return touchBarButton(
            identifier: identifier, title: "« Unstage All", image: nil,
            target: historyController.fileViewController,
            action: #selector(XTFileViewController.unstageAll(_:)))
      
      case NSTouchBarItemIdentifier.stageAll:
        return touchBarButton(
            identifier: identifier, title: "» Stage All", image: nil,
            target: historyController.fileViewController,
            action: #selector(XTFileViewController.stageAll(_:)))

      default:
        return nil
    }
  }
  
  @IBAction func showStaging(_ sender: Any?)
  {
    guard let outline = sidebarController.sidebarOutline
    else { return }
    let stagingRow = outline.row(forItem: sidebarController.sidebarDS.stagingItem)
  
    outline.selectRowIndexes(IndexSet(integer: stagingRow),
                             byExtendingSelection: false)
  }
}
