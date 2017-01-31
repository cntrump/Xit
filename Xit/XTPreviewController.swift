import Foundation
import Quartz

/// Controller for the QuickLook preview tab.
class XTPreviewController: NSViewController
{
}

extension XTPreviewController: XTFileContentController
{
  public func clear()
  {
    (view as! QLPreviewView).previewItem = nil
  }
  
  public func load(path: String!, model: XTFileChangesModel!, staged: Bool)
  {
    let previewView = view as! QLPreviewView
  
    if staged {
      var previewItem: XTPreviewItem! = previewView.previewItem
                                        as? XTPreviewItem
      
      if previewItem == nil {
        previewItem = XTPreviewItem()
        previewView.previewItem = previewItem
      }
      previewItem.model = model
      previewItem.path = path
      previewView.refreshPreviewItem()
    }
    else {
      guard let urlString = model.unstagedFileURL(path)?.absoluteString
      else {
        previewView.previewItem = nil
        return
      }
      // Swift's URL doesn't conform to QLPreviewItem because it's not a class
      let nsurl = NSURL(string: urlString)
    
      previewView.previewItem = nsurl
    }
  }
}