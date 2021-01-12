/*This file is part of Medito App.

Medito App is free software: you can redistribute it and/or modify
it under the terms of the Affero GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Medito App is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
Affero GNU General Public License for more details.

You should have received a copy of the Affero GNU General Public License
along with Medito App. If not, see <https://www.gnu.org/licenses/>.*/

import 'package:Medito/audioplayer/player_widget.dart';
import 'package:Medito/network/api_response.dart';
import 'package:Medito/network/folder/folder_bloc.dart';
import 'package:Medito/network/folder/folder_items.dart';
import 'package:Medito/tracking/tracking.dart';
import 'package:Medito/utils/colors.dart';
import 'package:Medito/utils/navigation.dart';
import 'package:Medito/utils/stats_utils.dart';
import 'package:Medito/utils/utils.dart';
import 'package:Medito/widgets/app_bar_widget.dart';
import 'package:Medito/widgets/folders/folder_list_item_widget.dart';
import 'package:Medito/widgets/folders/list_item_image_widget.dart';
import 'package:Medito/widgets/folders/loading_list_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FolderStateless extends StatelessWidget {
  FolderStateless({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FolderNavWidget();
  }
}

class FolderNavWidget extends StatefulWidget {
  FolderNavWidget({Key key, this.contentId}) : super(key: key);

  final String contentId;

  @override
  _FolderNavWidgetState createState() => _FolderNavWidgetState();
}

class _FolderNavWidgetState extends State<FolderNavWidget>
    with TickerProviderStateMixin {
  BuildContext scaffoldContext; //for the snackbar
  FolderItemsBloc _bloc;

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Tracking.changeScreenName(Tracking.FOLDER_PAGE);
    _bloc = FolderItemsBloc(widget.contentId);
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
    ));

    return Scaffold(
      body: Builder(
        builder: (BuildContext context) {
          scaffoldContext = context;
          return _buildSafeAreaBody();
        },
      ),
    );
  }

  //The AppBar Widget when an audio file is long pressed.
  Widget _buildSelectedAppBar() {
    return FutureBuilder<bool>(
        future: _bloc.selectedSessionListenedFuture,
        builder: (context, snapshot) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: AppBar(
              title: Text(''),
              leading: snapshot != null
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                      onPressed: () => _bloc.deselectItem())
                  : Container(),
              actions: <Widget>[
                snapshot != null &&
                        snapshot.connectionState != ConnectionState.waiting
                    ? IconButton(
                        tooltip: snapshot?.data != null && snapshot.data
                            ? 'Mark session as unlistened'
                            : 'Mark session as listened',
                        icon: Icon(
                          snapshot?.data != null && snapshot.data
                              ? Icons.undo
                              : Icons.check_circle,
                          color: MeditoColors.walterWhite,
                        ),
                        onPressed: () async {
                          if (snapshot != null && !snapshot.data) {
                            await markAsListened(_bloc.selectedItem.id);
                          } else {
                            await markAsNotListened(_bloc.selectedItem.id);
                          }
                          setState(() => _bloc.deselectItem());
                        })
                    : Container(),
              ],
              backgroundColor: MeditoColors.moonlight,
            ),
          );
        });
  }

  Widget _buildSafeAreaBody() {
    checkConnectivity().then((connected) {
      if (!connected) {
        createSnackBar('Check your connectivity', scaffoldContext);
      }
    });

    return SafeArea(
      bottom: false,
      maintainBottomViewPadding: false,
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                  child: Stack(
                children: <Widget>[
                  _getListView(),
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _getListView() {
    return RefreshIndicator(
      onRefresh: () => _bloc.fetchItemsList(widget.contentId),
      color: MeditoColors.walterWhite,
      backgroundColor: MeditoColors.moonlight,
      child: StreamBuilder<ApiResponse<List<FolderItem>>>(
          stream: _bloc.itemsListController.stream,
          builder: (context, itemsSnapshot) {
            if (itemsSnapshot.connectionState == ConnectionState.none) {
              return Text(
                'No connection. Please try again later',
                style: Theme.of(context).textTheme.headline3,
              );
            }

            if (itemsSnapshot.connectionState == ConnectionState.waiting ||
                itemsSnapshot.hasData == false ||
                itemsSnapshot.hasData == null) {
              return LoadingListWidget();
            }

            return ListView.builder(
                itemCount: 1 +
                    (itemsSnapshot.data == null
                        ? 0
                        : itemsSnapshot.data.body?.length ?? 0),
                shrinkWrap: true,
                itemBuilder: (BuildContext context, int i) {
                  if (i == 0) {
                    return _getAppBarStreamBuilder();
                  }
                  return Column(
                    children: <Widget>[
                      _getItemWidget(itemsSnapshot.data?.body[i - 1]),
                    ],
                  );
                });
          }),
    );
  }

  Widget _getAppBarStreamBuilder() {
    return StreamBuilder<AppBarState>(
        stream: _bloc.appbarStateController.stream,
        initialData: AppBarState.normal,
        builder: (context, state) {
          switch (state.data) {
            case AppBarState.selected:
              return _buildSelectedAppBar();
              break;
            case AppBarState.normal:
            default:
              return StreamBuilder<ApiResponse<String>>(
                  stream: _bloc.titleController.stream,
                  builder: (context, coverSnapshot) {
                    switch (coverSnapshot.data?.status) {
                      case Status.ERROR:
                        return MeditoAppBarWidget(title: '...');
                      case Status.COMPLETED:
                        return MeditoAppBarWidget(title: coverSnapshot.data?.body);
                      case Status.LOADING:
                        return MeditoAppBarWidget(title: '...');
                      default:
                        return Container();
                    }
                  });
              break;
          }
        });
  }

  void folderTap(FolderItem i) {
    Tracking.trackEvent(Tracking.TAP, Tracking.FOLDER_TAPPED, i.id);
    //if you tapped on a folder
    NavigationFactory.navigate(
        context, NavigationFactory.getScreenFromString(i.itemType),
        id: i.id);
  }

  void startService(media, primaryColor) {
    start(media, primaryColor).then((value) {
      NavigationFactory.navigate(context, Screen.player, id: null);
      return null;
    });
  }

  InkWell _getFileItemWidget(FolderItem item) {
    return InkWell(
        onTap: () => folderTap(item),
        splashColor: MeditoColors.moonlight,
        child: ListItemWidget(
          item: item,
        ));
  }

  SizedBox _getImageListItemWidget(FolderItem item) =>
      SizedBox(width: 300, child: ImageListItemWidget(src: 'item.'));

  InkWell _getItemWidget(FolderItem item) {
    return InkWell(
      onTap: () {
        if (_bloc.selectedItem != null) {
          setState(() {
            _bloc.itemLongPressed(_bloc.selectedItem);
          });
        } else {
          //FIXME here
          // fileTap(item);
        }
      },
      onLongPress: () {
        if (item.fileType == FileType.session) {
          setState(() {
            _bloc.itemLongPressed(item);
          });
        }
      },
      splashColor: MeditoColors.moonlight,
      child: Ink(
        color: (_bloc.selectedItem == null || _bloc.selectedItem.id != item.id)
            ? MeditoColors.darkMoon
            : MeditoColors.walterWhiteLine,
        child: _getFileItemWidget(item),
      ),
    );
  }
}